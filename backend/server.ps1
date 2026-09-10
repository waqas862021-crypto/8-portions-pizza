# CafeBot chat backend - zero-install, matches the same approach as
# serve.ps1 (uses .NET's built-in HttpListener; no Node/Python needed on
# this machine). One endpoint: POST /api/chat.
#
# Request body:  { "message": "...", "history": [{ "role": "user"|"assistant", "content": "..." }, ...], "sessionId": "..." (optional) }
# Response body: { "reply": "...", "sessionId": "...", "order": { ... } }
#
# CafeBot is grounded in data/menu.json (the only source of truth for
# menu items/prices) and prompts/system-prompt.md (its instructions).
#
# Order state: each session gets a simple structured order object (items,
# order type, customer details, promotion, total, confirmation, status),
# held in memory only in $script:Sessions for as long as this process
# runs - no database, nothing persisted to disk.
#
# Six ordering tools are implemented: add_item_to_order,
# modify_order_item, remove_order_item, apply_promotion,
# set_pickup_order and set_delivery_order (see Add-ItemToOrder /
# Update-OrderItem / Remove-OrderItem / Apply-Promotion /
# Set-PickupOrder / Set-DeliveryOrder below). Add/modify validate
# against data/menu.json - an item that requires an option
# (optionsRequired: true) can't be added or left without one, so the
# model has to ask the customer first.
#
# Fulfillment: set_pickup_order needs a customer name (optional pickup
# time). set_delivery_order needs a customer name, phone and full
# address (optional apartment/unit and delivery instructions). Both are
# safe to call more than once - each call only updates the fields it
# was actually given and reports back exactly which required fields are
# still missing, so the model asks only for what it doesn't already
# have and never guesses the rest.
#
# Promotions: the backend computes which data/promotions.json entries
# are both active and currently eligible (category/minOrderValue/day/
# time rules actually satisfied against the live order) and gives the
# model ONLY that pre-filtered list in the system message - never the
# raw promotions file - so it can't mention or apply a promotion that
# isn't real, active, or eligible. apply_promotion re-checks eligibility
# itself before touching the order.
#
# Checkout is not implemented yet - see prompts/system-prompt.md.
param([int]$Port = 8792)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$systemPromptPath = Join-Path $root "prompts\system-prompt.md"
$menuPath = Join-Path $root "data\menu.json"
$promotionsPath = Join-Path $root "data\promotions.json"
$envPath = Join-Path $root ".env"

$script:Sessions = @{}

function New-OrderState {
  return [ordered]@{
    items = @()
    orderType = $null
    customer = [ordered]@{ name = $null; phone = $null; address = $null; apartmentUnit = $null; notes = $null }
    pickupTime = $null
    promotion = $null
    total = 0
    confirmation = $false
    status = "draft"
  }
}

function Get-OrCreateSession([string]$sessionId) {
  if ([string]::IsNullOrWhiteSpace($sessionId)) {
    $sessionId = [guid]::NewGuid().ToString()
  }
  if (-not $script:Sessions.ContainsKey($sessionId)) {
    $script:Sessions[$sessionId] = New-OrderState
  }
  return @{ SessionId = $sessionId; Order = $script:Sessions[$sessionId] }
}

function Load-DotEnv([string]$path) {
  if (-not (Test-Path $path)) { return }
  Get-Content $path | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $idx = $_.IndexOf('=')
    if ($idx -gt 0) {
      $key = $_.Substring(0, $idx).Trim()
      $value = $_.Substring($idx + 1).Trim()
      [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
  }
}

Load-DotEnv $envPath

function Get-Menu {
  return Get-Content $menuPath -Raw | ConvertFrom-Json
}

function Get-Promotions {
  return (Get-Content $promotionsPath -Raw | ConvertFrom-Json).promotions
}

function Get-MenuItemCategory($menu, [string]$menuItemId) {
  $item = $menu.items | Where-Object { $_.id -eq $menuItemId } | Select-Object -First 1
  if ($item) { return $item.category }
  return $null
}

function Test-DayEligible($days, [datetime]$now) {
  if (-not $days -or @($days).Count -eq 0) { return $true }
  $today = $now.DayOfWeek.ToString().ToLower()
  return (@($days) | ForEach-Object { "$_".ToLower() }) -contains $today
}

function Test-TimeWindow($timeWindow, [datetime]$now) {
  if (-not $timeWindow -or -not $timeWindow.start -or -not $timeWindow.end) { return $true }
  $nowMinutes = $now.Hour * 60 + $now.Minute
  $start = [datetime]::ParseExact($timeWindow.start, "HH:mm", $null)
  $end = [datetime]::ParseExact($timeWindow.end, "HH:mm", $null)
  $startMinutes = $start.Hour * 60 + $start.Minute
  $endMinutes = $end.Hour * 60 + $end.Minute
  return $nowMinutes -ge $startMinutes -and $nowMinutes -le $endMinutes
}

# Checks a promotion's eligibility rules against the live order/menu/
# clock. Supports the three eligibility shapes used in
# data/promotions.json: "categories" (discount applies to every order
# item in those categories), "requiresCategories" + "appliesToCategory"
# (buy from one category, discount an item in another), or neither
# (a plain whole-order discount, gated only by minOrderValue/days/time).
# Returns { eligible; reason; matchedItems } - matchedItems is what the
# discount amount should be computed against.
function Test-PromotionEligibility($promo, $order, $menu, [datetime]$now) {
  if (-not $promo.active) {
    return @{ eligible = $false; reason = "not active" }
  }

  $minOrderValue = if ($null -ne $promo.eligibility.minOrderValue) { [double]$promo.eligibility.minOrderValue } else { 0 }
  if ([double]$order.total -lt $minOrderValue) {
    return @{ eligible = $false; reason = "order total is below the required minimum ($minOrderValue)" }
  }

  if (-not (Test-DayEligible $promo.eligibility.days $now)) {
    return @{ eligible = $false; reason = "not valid today" }
  }

  if (-not (Test-TimeWindow $promo.eligibility.timeWindow $now)) {
    return @{ eligible = $false; reason = "not valid at this time" }
  }

  if ($promo.eligibility.categories) {
    $categories = @($promo.eligibility.categories)
    $matched = @()
    foreach ($lineItem in $order.items) {
      $cat = Get-MenuItemCategory $menu $lineItem.menuItemId
      if ($cat -and ($categories -contains $cat)) { $matched += $lineItem }
    }
    if ($matched.Count -eq 0) {
      return @{ eligible = $false; reason = "no items from an eligible category ($($categories -join ', ')) in the order" }
    }
    return @{ eligible = $true; reason = $null; matchedItems = $matched }
  }

  if ($promo.eligibility.requiresCategories -and $promo.eligibility.appliesToCategory) {
    foreach ($reqCat in @($promo.eligibility.requiresCategories)) {
      $hasReq = $false
      foreach ($lineItem in $order.items) {
        if ((Get-MenuItemCategory $menu $lineItem.menuItemId) -eq $reqCat) { $hasReq = $true; break }
      }
      if (-not $hasReq) {
        return @{ eligible = $false; reason = "order needs an item from category '$reqCat' first" }
      }
    }
    $applyCat = $promo.eligibility.appliesToCategory
    $matched = @()
    foreach ($lineItem in $order.items) {
      if ((Get-MenuItemCategory $menu $lineItem.menuItemId) -eq $applyCat) { $matched += $lineItem }
    }
    if ($matched.Count -eq 0) {
      return @{ eligible = $false; reason = "no item from category '$applyCat' in the order to apply the discount to" }
    }
    return @{ eligible = $true; reason = $null; matchedItems = @($matched[0]) }
  }

  # No category rule at all - a plain whole-order discount.
  if ($order.items.Count -eq 0) {
    return @{ eligible = $false; reason = "order is empty" }
  }
  return @{ eligible = $true; reason = $null; matchedItems = $order.items }
}

# Computes the SAR amount a promotion is worth right now, capped so it
# never exceeds the value of what it's discounting.
function Get-PromotionDiscountAmount($promo, $order, $matchedItems) {
  if ($promo.eligibility.categories) {
    $base = (($matchedItems | ForEach-Object { [double]$_.lineTotal }) | Measure-Object -Sum).Sum
  } elseif ($promo.eligibility.requiresCategories -and $promo.eligibility.appliesToCategory) {
    $base = [double]$matchedItems[0].lineTotal
  } else {
    $base = [double]$order.total
  }

  if ($promo.discount.type -eq "percentage") {
    $amount = $base * ([double]$promo.discount.value / 100)
  } else {
    $amount = [double]$promo.discount.value
  }
  if ($amount -gt $base) { $amount = $base }
  if ($amount -lt 0) { $amount = 0 }
  return [math]::Round($amount, 2)
}

# Active promotions that are ALSO currently eligible for this specific
# order - the only ones the model is allowed to see, mention or apply.
function Get-EligiblePromotions($order, $menu, $promotions, [datetime]$now) {
  $eligible = @()
  foreach ($promo in $promotions) {
    if (-not $promo.active) { continue }
    $test = Test-PromotionEligibility $promo $order $menu $now
    if ($test.eligible) {
      $amount = Get-PromotionDiscountAmount $promo $order $test.matchedItems
      $eligible += [ordered]@{ id = $promo.id; name = $promo.name; rule = $promo.rule; estimatedDiscount = $amount }
    }
  }
  return $eligible
}

function Format-PromotionsSummary($eligiblePromotions, [string]$currency) {
  if (-not $eligiblePromotions -or $eligiblePromotions.Count -eq 0) {
    return "No promotions are currently eligible for this order."
  }
  $lines = foreach ($p in $eligiblePromotions) {
    $amountText = "{0:0.00}" -f [double]$p.estimatedDiscount
    "- [$($p.id)] $($p.name): $($p.rule) (estimated discount: $currency $amountText)"
  }
  return ($lines -join "`n")
}

# Plain-text, human-readable order summary (quantities + chosen options
# spelled out) so the model can relay it to the customer directly
# instead of reconstructing one from the raw order JSON each time.
function Format-OrderSummary($order, [string]$currency) {
  if (-not $order.items -or $order.items.Count -eq 0) {
    return "No items yet."
  }
  $lines = foreach ($lineItem in $order.items) {
    $optionLabels = @($lineItem.selectedOptions | ForEach-Object { $_.label })
    $optionText = if ($optionLabels.Count -gt 0) { " (" + ($optionLabels -join ", ") + ")" } else { "" }
    $lineTotalText = "{0:0.00}" -f [double]$lineItem.lineTotal
    "- $($lineItem.quantity)x $($lineItem.name)$optionText - $currency $lineTotalText"
  }
  $totalText = "{0:0.00}" -f [double]$order.total
  return ($lines -join "`n") + "`nTotal: $currency $totalText"
}

function Build-SystemMessage([hashtable]$order, [array]$eligiblePromotions) {
  $systemPrompt = Get-Content $systemPromptPath -Raw
  $menuJson = Get-Content $menuPath -Raw
  $menu = $menuJson | ConvertFrom-Json
  $orderJson = $order | ConvertTo-Json -Depth 10
  $orderSummary = Format-OrderSummary $order $menu.currency
  $promotionsSummary = Format-PromotionsSummary $eligiblePromotions $menu.currency
  $menuHeading = "Current menu data (data/menu.json, authoritative - do not invent items or prices beyond this):"
  $orderHeading = "Current order state for this session (you may only change it by calling add_item_to_order, modify_order_item, remove_order_item, apply_promotion, set_pickup_order or set_delivery_order - each item's lineItemId is how you refer to it; check customer.name/phone/address/apartmentUnit/notes and pickupTime here before asking the customer for them - never re-ask for something already set, and never guess a value that isn't):"
  $summaryHeading = "Concise order summary (use this, as-is or lightly reworded, whenever the customer asks what's in their order - don't recompute it from the raw JSON above):"
  $promotionsHeading = "Currently eligible active promotions (this list is already filtered to what's active AND eligible right now - you may only mention or apply a promotion from this exact list, by its id, via apply_promotion; never mention or apply any promotion not listed here, and never invent a discount):"
  return $systemPrompt + "`n`n" + $menuHeading + "`n" + $menuJson + "`n`n" + $orderHeading + "`n" + $orderJson + "`n`n" + $summaryHeading + "`n" + $orderSummary + "`n`n" + $promotionsHeading + "`n" + $promotionsSummary
}

function Get-ToolDefinitions {
  return @(
    @{
      type = "function"
      function = @{
        name = "add_item_to_order"
        description = "Add one valid menu item to the customer's current order. Only call this with a real menuItemId from the menu data. If the item's optionsRequired is true, first ask the customer to pick one of its options and pass its id in selectedOptionIds - calling this without a required option will fail."
        parameters = @{
          type = "object"
          properties = @{
            menuItemId = @{ type = "string"; description = "Exact id of the item from the menu data (data/menu.json)." }
            quantity = @{ type = "integer"; minimum = 1 }
            selectedOptionIds = @{ type = "array"; items = @{ type = "string" }; description = "ids of any chosen options for this item (e.g. a size or milk choice)." }
          }
          required = @("menuItemId", "quantity")
        }
      }
    },
    @{
      type = "function"
      function = @{
        name = "modify_order_item"
        description = "Change the quantity and/or chosen options (size, milk type, add-ons, etc.) of an item already in the order. Only call this with a real lineItemId from the current order state. Provide quantity and/or selectedOptionIds - whichever the customer wants changed; selectedOptionIds, if given, completely replaces the item's previous option choices, so include every option that should still apply, not just the new one."
        parameters = @{
          type = "object"
          properties = @{
            lineItemId = @{ type = "string"; description = "id of the existing order line to change (from the current order state)." }
            quantity = @{ type = "integer"; minimum = 1; description = "New quantity, if changing it." }
            selectedOptionIds = @{ type = "array"; items = @{ type = "string" }; description = "Full replacement set of option ids for this line, if changing size/customizations." }
          }
          required = @("lineItemId")
        }
      }
    },
    @{
      type = "function"
      function = @{
        name = "remove_order_item"
        description = "Remove an item from the order, in full or partially. Only call this with a real lineItemId from the current order state. Omit quantity (or give a quantity that is greater than or equal to what's currently ordered) to remove the whole line; give a smaller quantity to reduce it by that amount instead."
        parameters = @{
          type = "object"
          properties = @{
            lineItemId = @{ type = "string"; description = "id of the existing order line to remove or reduce (from the current order state)." }
            quantity = @{ type = "integer"; minimum = 1; description = "How many units to remove. Omit to remove the entire line." }
          }
          required = @("lineItemId")
        }
      }
    },
    @{
      type = "function"
      function = @{
        name = "apply_promotion"
        description = "Apply one promotion to the current order, by its id. Only call this with a promotionId that appears in the 'Currently eligible active promotions' list in the system context - that list is already filtered to what's active and eligible for this exact order, so never call this with an id you weren't given there. Only one promotion can be applied per order."
        parameters = @{
          type = "object"
          properties = @{
            promotionId = @{ type = "string"; description = "id of the promotion to apply, from the eligible promotions list." }
          }
          required = @("promotionId")
        }
      }
    },
    @{
      type = "function"
      function = @{
        name = "set_pickup_order"
        description = "Select pickup as the order type and record the customer's name (required) and, optionally, when they want to pick it up. Check the current order state first and only ask the customer for whatever is still missing (customer.name / pickupTime) - you can call this once with just the name and again later to add a pickup time, or provide both at once."
        parameters = @{
          type = "object"
          properties = @{
            customerName = @{ type = "string"; description = "Customer's name for the pickup order. Required unless it's already set in the current order state." }
            pickupTime = @{ type = "string"; description = "When the customer wants to pick up, in their own words (e.g. '6:30 PM', 'ASAP', 'in 20 minutes'). Optional." }
          }
          required = @()
        }
      }
    },
    @{
      type = "function"
      function = @{
        name = "set_delivery_order"
        description = "Select delivery as the order type and record the customer's name, phone number and full delivery address (all required), plus an apartment/unit number and delivery instructions if given (both optional). Check the current order state first and only ask for whatever is still missing - call this incrementally as information comes in; it reports back exactly which required fields are still missing until all three are provided. Never guess or fill in any of these fields - only use what the customer actually told you."
        parameters = @{
          type = "object"
          properties = @{
            customerName = @{ type = "string"; description = "Customer's name. Required." }
            phone = @{ type = "string"; description = "Customer's phone number. Required." }
            address = @{ type = "string"; description = "Full delivery address. Required." }
            apartmentUnit = @{ type = "string"; description = "Apartment or unit number, if applicable. Optional." }
            instructions = @{ type = "string"; description = "Delivery instructions, e.g. gate code, landmark, leave at door. Optional." }
          }
          required = @()
        }
      }
    }
  )
}

# Validates menuItemId/quantity/selectedOptionIds against the live menu
# data and, if valid, appends a line item to $order (mutated in place -
# hashtables are reference types in PowerShell) and recomputes the total.
# Returns a plain result object describing success or exactly what was
# invalid, so the model can relay that back to the customer.
function Add-ItemToOrder($order, $menu, [string]$menuItemId, $quantity, $selectedOptionIds) {
  $item = $menu.items | Where-Object { $_.id -eq $menuItemId } | Select-Object -First 1
  if (-not $item) {
    return @{ ok = $false; error = "No menu item with id '$menuItemId'. It is not on the menu." }
  }
  if (-not $item.available) {
    return @{ ok = $false; error = "'$($item.name)' is currently unavailable." }
  }

  $qty = 0
  if (-not [int]::TryParse("$quantity", [ref]$qty) -or $qty -lt 1) {
    return @{ ok = $false; error = "Quantity must be a whole number of 1 or more." }
  }

  $chosenIds = @($selectedOptionIds | Where-Object { $_ })
  $matchedOptions = @()
  foreach ($optId in $chosenIds) {
    $opt = $item.options | Where-Object { $_.id -eq $optId } | Select-Object -First 1
    if (-not $opt) {
      return @{ ok = $false; error = "'$optId' is not a valid option for '$($item.name)'."; validOptions = $item.options }
    }
    $matchedOptions += $opt
  }

  if ($item.optionsRequired -and $matchedOptions.Count -eq 0) {
    return @{ ok = $false; error = "'$($item.name)' requires choosing an option before it can be added."; requiredOptions = $item.options }
  }

  $unitPrice = [double]$item.price
  foreach ($opt in $matchedOptions) { $unitPrice += [double]$opt.priceModifier }
  $lineTotal = [math]::Round($unitPrice * $qty, 2)

  $lineItem = [ordered]@{
    lineItemId = [guid]::NewGuid().ToString()
    menuItemId = $item.id
    name = $item.name
    quantity = $qty
    selectedOptions = $matchedOptions
    unitPrice = [math]::Round($unitPrice, 2)
    lineTotal = $lineTotal
  }

  $order.items += $lineItem
  Update-OrderTotal $order

  return @{ ok = $true; added = $lineItem }
}

function Update-OrderTotal($order) {
  $itemsTotal = if ($order.items.Count -gt 0) { (($order.items | ForEach-Object { [double]$_.lineTotal }) | Measure-Object -Sum).Sum } else { 0 }
  $discount = if ($order.promotion) { [double]$order.promotion.discountAmount } else { 0 }
  # [math]::Max(0, ...) would resolve to the Int32 overload here (0 is an
  # int literal) and silently truncate the result to a whole number -
  # 0.0 forces the Double overload instead.
  $order.total = [math]::Round([math]::Max(0.0, $itemsTotal - $discount), 2)
}

# Changes quantity and/or the selected options of an existing line item,
# re-validating against the live menu data the same way Add-ItemToOrder
# does (unknown/invalid options rejected, optionsRequired still
# enforced). selectedOptionIds, when given, fully replaces the line's
# previous options. Mutates $order in place; returns ok/error like
# Add-ItemToOrder.
function Update-OrderItem($order, $menu, [string]$lineItemId, $quantity, $selectedOptionIds) {
  $lineItem = $order.items | Where-Object { $_.lineItemId -eq $lineItemId } | Select-Object -First 1
  if (-not $lineItem) {
    return @{ ok = $false; error = "No order item with lineItemId '$lineItemId'." }
  }

  $item = $menu.items | Where-Object { $_.id -eq $lineItem.menuItemId } | Select-Object -First 1
  if (-not $item -or -not $item.available) {
    return @{ ok = $false; error = "'$($lineItem.name)' is no longer available, so it can't be modified." }
  }

  $hasQuantity = $null -ne $quantity -and "$quantity" -ne ""
  $hasOptions = $null -ne $selectedOptionIds
  if (-not $hasQuantity -and -not $hasOptions) {
    return @{ ok = $false; error = "Nothing to update - provide a new quantity and/or selectedOptionIds." }
  }

  $qty = $lineItem.quantity
  if ($hasQuantity) {
    $parsedQty = 0
    if (-not [int]::TryParse("$quantity", [ref]$parsedQty) -or $parsedQty -lt 1) {
      return @{ ok = $false; error = "Quantity must be a whole number of 1 or more." }
    }
    $qty = $parsedQty
  }

  $matchedOptions = $lineItem.selectedOptions
  if ($hasOptions) {
    $chosenIds = @($selectedOptionIds | Where-Object { $_ })
    $newMatched = @()
    foreach ($optId in $chosenIds) {
      $opt = $item.options | Where-Object { $_.id -eq $optId } | Select-Object -First 1
      if (-not $opt) {
        return @{ ok = $false; error = "'$optId' is not a valid option for '$($item.name)'."; validOptions = $item.options }
      }
      $newMatched += $opt
    }
    if ($item.optionsRequired -and $newMatched.Count -eq 0) {
      return @{ ok = $false; error = "'$($item.name)' requires choosing an option - it can't be left without one."; requiredOptions = $item.options }
    }
    $matchedOptions = $newMatched
  }

  $unitPrice = [double]$item.price
  foreach ($opt in $matchedOptions) { $unitPrice += [double]$opt.priceModifier }

  $lineItem.quantity = $qty
  $lineItem.selectedOptions = $matchedOptions
  $lineItem.unitPrice = [math]::Round($unitPrice, 2)
  $lineItem.lineTotal = [math]::Round($unitPrice * $qty, 2)

  Update-OrderTotal $order

  return @{ ok = $true; updated = $lineItem }
}

# Removes an existing line item, in full or partially. With no quantity
# (or one at least as large as what's ordered) the whole line is
# dropped; with a smaller quantity the line's quantity is reduced by
# that amount and kept. Mutates $order in place; returns ok/error like
# Add-ItemToOrder / Update-OrderItem.
function Remove-OrderItem($order, [string]$lineItemId, $quantity) {
  $lineItem = $order.items | Where-Object { $_.lineItemId -eq $lineItemId } | Select-Object -First 1
  if (-not $lineItem) {
    return @{ ok = $false; error = "No order item with lineItemId '$lineItemId'." }
  }

  $removeQty = $lineItem.quantity
  $hasQuantity = $null -ne $quantity -and "$quantity" -ne ""
  if ($hasQuantity) {
    $parsedQty = 0
    if (-not [int]::TryParse("$quantity", [ref]$parsedQty) -or $parsedQty -lt 1) {
      return @{ ok = $false; error = "Quantity to remove must be a whole number of 1 or more." }
    }
    $removeQty = $parsedQty
  }

  if ($removeQty -ge $lineItem.quantity) {
    $order.items = @($order.items | Where-Object { $_.lineItemId -ne $lineItemId })
    Update-OrderTotal $order
    return @{ ok = $true; removed = $lineItem }
  }

  $lineItem.quantity -= $removeQty
  $lineItem.lineTotal = [math]::Round([double]$lineItem.unitPrice * $lineItem.quantity, 2)
  Update-OrderTotal $order

  return @{ ok = $true; updated = $lineItem }
}

# Applies one promotion by id, re-checking its eligibility against the
# live order (not just trusting an earlier snapshot) so nothing gets
# applied that isn't actually active/eligible right now. Only one
# promotion may be applied at a time - no stacking. On success, sets
# $order.promotion (the discount is locked in at that amount; it isn't
# re-derived if the order changes afterwards) and recomputes the total
# via Update-OrderTotal.
function Apply-Promotion($order, $menu, $promotions, [string]$promotionId, [datetime]$now) {
  if ($order.promotion) {
    return @{ ok = $false; error = "A promotion is already applied to this order ('$($order.promotion.name)')." }
  }

  $promo = $promotions | Where-Object { $_.id -eq $promotionId } | Select-Object -First 1
  if (-not $promo) {
    return @{ ok = $false; error = "No promotion with id '$promotionId'." }
  }

  $test = Test-PromotionEligibility $promo $order $menu $now
  if (-not $test.eligible) {
    return @{ ok = $false; error = "'$($promo.name)' is not eligible right now: $($test.reason)." }
  }

  $amount = Get-PromotionDiscountAmount $promo $order $test.matchedItems

  $order.promotion = [ordered]@{ id = $promo.id; name = $promo.name; discountAmount = $amount }
  Update-OrderTotal $order

  return @{ ok = $true; applied = $order.promotion; newTotal = $order.total }
}

# Selects pickup as the order type and stores the customer name
# (required) and an optional pickup time. Safe to call more than once -
# each call only updates the fields it was actually given, so the model
# can set the name now and add a pickup time later without re-sending
# the name. Mutates $order in place.
function Set-PickupOrder($order, $customerName, $pickupTime) {
  if (-not [string]::IsNullOrWhiteSpace("$customerName")) {
    $order.customer.name = "$customerName".Trim()
  }

  if ([string]::IsNullOrWhiteSpace("$($order.customer.name)")) {
    return @{ ok = $false; error = "Customer name is required for pickup - ask for it."; missing = @("customerName") }
  }

  $order.orderType = "pickup"

  if (-not [string]::IsNullOrWhiteSpace("$pickupTime")) {
    $order.pickupTime = "$pickupTime".Trim()
  }

  return @{ ok = $true; orderType = $order.orderType; customerName = $order.customer.name; pickupTime = $order.pickupTime }
}

# Selects delivery as the order type once name, phone and address are
# all known (apartmentUnit and instructions are optional extras). Safe
# to call more than once, same as Set-PickupOrder: each call only
# updates the fields it was actually given, merging onto whatever was
# already stored, and reports exactly which required fields are still
# missing until all three are present - never fills in a missing field
# with a guess. Mutates $order in place.
function Set-DeliveryOrder($order, $customerName, $phone, $address, $apartmentUnit, $instructions) {
  if (-not [string]::IsNullOrWhiteSpace("$customerName")) {
    $order.customer.name = "$customerName".Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace("$phone")) {
    $order.customer.phone = "$phone".Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace("$address")) {
    $order.customer.address = "$address".Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace("$apartmentUnit")) {
    $order.customer.apartmentUnit = "$apartmentUnit".Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace("$instructions")) {
    $order.customer.notes = "$instructions".Trim()
  }

  $missing = @()
  if ([string]::IsNullOrWhiteSpace("$($order.customer.name)")) { $missing += "customerName" }
  if ([string]::IsNullOrWhiteSpace("$($order.customer.phone)")) { $missing += "phone" }
  if ([string]::IsNullOrWhiteSpace("$($order.customer.address)")) { $missing += "address" }

  if ($missing.Count -gt 0) {
    return @{ ok = $false; error = "Missing required delivery details: $($missing -join ', ') - ask the customer for these, don't guess."; missing = $missing }
  }

  $order.orderType = "delivery"

  return @{
    ok = $true
    orderType = $order.orderType
    customerName = $order.customer.name
    phone = $order.customer.phone
    address = $order.customer.address
    apartmentUnit = $order.customer.apartmentUnit
    instructions = $order.customer.notes
  }
}

function Invoke-AiChatCompletion([array]$messages, [array]$tools) {
  $apiKey = $env:AI_API_KEY
  $baseUrl = $env:AI_API_BASE_URL
  $model = $env:AI_MODEL_NAME

  if ([string]::IsNullOrWhiteSpace($apiKey) -or [string]::IsNullOrWhiteSpace($baseUrl) -or [string]::IsNullOrWhiteSpace($model)) {
    throw "AI API is not configured. Set AI_API_KEY, AI_API_BASE_URL and AI_MODEL_NAME in .env (see .env.example)."
  }

  $payload = @{ model = $model; messages = $messages }
  if ($tools) { $payload.tools = $tools }
  $body = $payload | ConvertTo-Json -Depth 10
  $headers = @{ Authorization = "Bearer $apiKey" }
  $endpoint = $baseUrl.TrimEnd('/') + "/chat/completions"

  $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -ContentType "application/json" -Body $body
  return $response.choices[0].message
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "CafeBot chat backend listening on http://localhost:$Port/api/chat"

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $req = $context.Request
  $res = $context.Response
  $res.ContentType = "application/json"

  try {
    if ($req.HttpMethod -ne "POST" -or $req.Url.AbsolutePath -ne "/api/chat") {
      $res.StatusCode = 404
      $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Not found. POST /api/chat only."}')
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
      $bodyText = $reader.ReadToEnd()
      $payload = $bodyText | ConvertFrom-Json

      $message = "$($payload.message)".Trim()
      if ([string]::IsNullOrWhiteSpace($message)) {
        throw "Missing required field: message"
      }

      $session = Get-OrCreateSession "$($payload.sessionId)"
      $menu = Get-Menu
      $promotions = Get-Promotions
      $now = Get-Date
      $eligiblePromotions = Get-EligiblePromotions $session.Order $menu $promotions $now

      $messages = @(@{ role = "system"; content = Build-SystemMessage $session.Order $eligiblePromotions })
      if ($payload.history) {
        foreach ($turn in $payload.history) {
          if ($turn.role -eq "user" -or $turn.role -eq "assistant") {
            $messages += @{ role = "$($turn.role)"; content = "$($turn.content)" }
          }
        }
      }
      $messages += @{ role = "user"; content = $message }

      $tools = Get-ToolDefinitions
      $assistantMessage = Invoke-AiChatCompletion $messages $tools

      if ($assistantMessage.tool_calls) {
        $messages += $assistantMessage

        foreach ($toolCall in $assistantMessage.tool_calls) {
          $args = $toolCall.function.arguments | ConvertFrom-Json
          if ($toolCall.function.name -eq "add_item_to_order") {
            $result = Add-ItemToOrder $session.Order $menu $args.menuItemId $args.quantity @($args.selectedOptionIds)
          } elseif ($toolCall.function.name -eq "modify_order_item") {
            $optionIds = if ($null -ne $args.selectedOptionIds) { @($args.selectedOptionIds) } else { $null }
            $result = Update-OrderItem $session.Order $menu $args.lineItemId $args.quantity $optionIds
          } elseif ($toolCall.function.name -eq "remove_order_item") {
            $result = Remove-OrderItem $session.Order $args.lineItemId $args.quantity
          } elseif ($toolCall.function.name -eq "apply_promotion") {
            $result = Apply-Promotion $session.Order $menu $promotions $args.promotionId $now
          } elseif ($toolCall.function.name -eq "set_pickup_order") {
            $result = Set-PickupOrder $session.Order $args.customerName $args.pickupTime
          } elseif ($toolCall.function.name -eq "set_delivery_order") {
            $result = Set-DeliveryOrder $session.Order $args.customerName $args.phone $args.address $args.apartmentUnit $args.instructions
          } else {
            $result = @{ ok = $false; error = "Unknown tool: $($toolCall.function.name)" }
          }
          $messages += @{ role = "tool"; tool_call_id = $toolCall.id; content = ($result | ConvertTo-Json -Depth 10) }
        }

        # One follow-up call (no tools this round) so the model turns the
        # tool result(s) into a normal reply for the customer.
        $assistantMessage = Invoke-AiChatCompletion $messages $null
      }

      $reply = $assistantMessage.content

      $json = @{ reply = $reply; sessionId = $session.SessionId; order = $session.Order } | ConvertTo-Json -Depth 10
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    }
  } catch {
    $res.StatusCode = 500
    $errJson = @{ error = "$($_.Exception.Message)" } | ConvertTo-Json
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } finally {
    $res.OutputStream.Close()
  }
}
