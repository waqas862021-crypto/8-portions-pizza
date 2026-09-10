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
# Delivery address confirmation: order.customer.addressConfirmed tracks
# whether the customer has explicitly confirmed the address is correct
# (see confirm_delivery_address / Confirm-DeliveryAddress). Any address
# change via set_delivery_order resets it to false, so a correction
# always requires re-confirmation. The model is told (system prompt) to
# read the address back and get explicit confirmation before checkout -
# this flag is what makes that state durable instead of just trusted
# conversationally.
#
# Promotions: the backend computes which data/promotions.json entries
# are both active and currently eligible (category/minOrderValue/day/
# time rules actually satisfied against the live order) and gives the
# model ONLY that pre-filtered list in the system message - never the
# raw promotions file - so it can't mention or apply a promotion that
# isn't real, active, or eligible. apply_promotion re-checks eligibility
# itself before touching the order.
#
# Pricing: order.subtotal/tax/deliveryFee/total are always recomputed by
# Update-OrderTotal from menu prices, quantities, the applied promotion
# and this flat TAX_RATE/DELIVERY_FEE config - plain arithmetic in
# PowerShell. The model is never asked to calculate or state a price
# itself; it only relays whatever the backend already computed (via the
# order state / concise order summary in the system message).
#
# Once the customer explicitly confirms (see Confirm-Order below), the
# order is saved to data/orders.json as a durable record with a unique
# orderId, a confirmedAt timestamp and status "confirmed" - the only
# persistence in this backend; everything else lives only in
# $script:Sessions for the life of the process. A draft can never be
# saved: Save-ConfirmedOrder is only ever called from inside Confirm-
# Order, after it has already verified the order is genuinely complete.
#
# Payment / fulfillment handoff beyond that save is not implemented yet
# - see prompts/system-prompt.md.
#
# A minimal staff dashboard (GET /dashboard, served from
# backend/dashboard.html) lists saved orders (GET /api/orders) and lets
# staff change an order's status (POST /api/orders/status). It has no
# authentication - same zero-install, local/trusted-use assumption as
# the rest of this backend, not meant to be exposed beyond that.
param([int]$Port = 8792)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$systemPromptPath = Join-Path $root "prompts\system-prompt.md"
$menuPath = Join-Path $root "data\menu.json"
$promotionsPath = Join-Path $root "data\promotions.json"
$ordersPath = Join-Path $root "data\orders.json"
$dashboardPath = Join-Path $PSScriptRoot "dashboard.html"
$envPath = Join-Path $root ".env"

# The states staff can move a saved order through. Deliberately flat -
# no enforced transition order (e.g. nothing stops moving straight from
# "confirmed" to "completed") to keep this minimal.
$script:OrderStatuses = @("confirmed", "preparing", "ready", "completed", "cancelled")

$script:Sessions = @{}

function New-OrderState {
  return [ordered]@{
    items = @()
    orderType = $null
    customer = [ordered]@{ name = $null; phone = $null; address = $null; apartmentUnit = $null; notes = $null; addressConfirmed = $false }
    pickupTime = $null
    promotion = $null
    subtotal = 0
    tax = 0
    deliveryFee = 0
    total = 0
    confirmation = $false
    status = "draft"
    orderId = $null
    confirmedAt = $null
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

# Simple flat pricing config, not per-item menu data: TAX_RATE is a
# percentage applied to the discounted items subtotal (e.g. 15 means
# 15%); DELIVERY_FEE is a flat SAR amount charged only on delivery
# orders. Both default to 0 (TryParse leaves them at 0 if the .env
# variable is missing or not a number), so pricing still works with no
# .env at all.
$script:TaxRatePercent = 0.0
[void][double]::TryParse("$env:TAX_RATE", [ref]$script:TaxRatePercent)
$script:DeliveryFeeAmount = 0.0
[void][double]::TryParse("$env:DELIVERY_FEE", [ref]$script:DeliveryFeeAmount)

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
  if ([double]$order.subtotal -lt $minOrderValue) {
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
    $base = [double]$order.subtotal
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

  $totalLines = @("Subtotal: $currency " + ("{0:0.00}" -f [double]$order.subtotal))
  if ($order.promotion) {
    $totalLines += "Discount ($($order.promotion.name)): -$currency " + ("{0:0.00}" -f [double]$order.promotion.discountAmount)
  }
  if ([double]$order.tax -gt 0) {
    $totalLines += "Tax: $currency " + ("{0:0.00}" -f [double]$order.tax)
  }
  if ([double]$order.deliveryFee -gt 0) {
    $totalLines += "Delivery fee: $currency " + ("{0:0.00}" -f [double]$order.deliveryFee)
  }
  $totalLines += "Total: $currency " + ("{0:0.00}" -f [double]$order.total)

  return ($lines -join "`n") + "`n" + ($totalLines -join "`n")
}

# Complete, structured summary for the customer to review right before
# checkout (or whenever they want everything at once): items with
# quantities/customizations and the price breakdown (reuses
# Format-OrderSummary), fulfillment details for whichever order type is
# selected, and promotions (the applied one, or the currently valid ones
# if none is applied yet). Built entirely from already-computed
# order/menu data - nothing here is left for the model to assemble or
# calculate itself.
function Format-CheckoutSummary($order, [array]$eligiblePromotions, [string]$currency) {
  $itemsSection = Format-OrderSummary $order $currency

  $fulfillmentLines = @()
  if ($order.orderType -eq "pickup") {
    $fulfillmentLines += "Type: Pickup"
    $fulfillmentLines += "Name: $($order.customer.name)"
    $fulfillmentLines += "Pickup time: $(if ($order.pickupTime) { $order.pickupTime } else { 'not specified' })"
  } elseif ($order.orderType -eq "delivery") {
    $fulfillmentLines += "Type: Delivery"
    $fulfillmentLines += "Name: $($order.customer.name)"
    $fulfillmentLines += "Phone: $($order.customer.phone)"
    $addressLine = "Address: $($order.customer.address)"
    if ($order.customer.apartmentUnit) { $addressLine += ", $($order.customer.apartmentUnit)" }
    $fulfillmentLines += $addressLine
    if ($order.customer.notes) { $fulfillmentLines += "Delivery instructions: $($order.customer.notes)" }
    $fulfillmentLines += "Address confirmed: $(if ($order.customer.addressConfirmed) { 'Yes' } else { 'No - must be confirmed before checkout' })"
  } else {
    $fulfillmentLines += "Not selected yet - ask whether this is pickup or delivery."
  }

  $promotionLines = @()
  if ($order.promotion) {
    $promotionLines += "Applied: $($order.promotion.name) (-$currency $("{0:0.00}" -f [double]$order.promotion.discountAmount))"
  } elseif ($eligiblePromotions -and $eligiblePromotions.Count -gt 0) {
    $promotionLines += "None applied. Currently valid:"
    $promotionLines += Format-PromotionsSummary $eligiblePromotions $currency
  } else {
    $promotionLines += "None applied or currently valid."
  }

  $confirmationLine = if ($order.confirmation) {
    "Already confirmed by the customer."
  } else {
    "Not yet confirmed - present this summary and get an explicit, unambiguous yes from the customer before calling confirm_order. A vague or hedging reply does not count."
  }

  return "Items:`n$itemsSection`n`nFulfillment:`n" + ($fulfillmentLines -join "`n") + "`n`nPromotions:`n" + ($promotionLines -join "`n") + "`n`nConfirmation:`n$confirmationLine"
}

function Build-SystemMessage([hashtable]$order, [array]$eligiblePromotions) {
  $systemPrompt = Get-Content $systemPromptPath -Raw
  $menuJson = Get-Content $menuPath -Raw
  $menu = $menuJson | ConvertFrom-Json
  $orderJson = $order | ConvertTo-Json -Depth 10
  $orderSummary = Format-OrderSummary $order $menu.currency
  $promotionsSummary = Format-PromotionsSummary $eligiblePromotions $menu.currency
  $checkoutSummary = Format-CheckoutSummary $order $eligiblePromotions $menu.currency
  $menuHeading = "Current menu data (data/menu.json, authoritative - do not invent items or prices beyond this):"
  $orderHeading = "Current order state for this session (you may only change it by calling add_item_to_order, modify_order_item, remove_order_item, apply_promotion, set_pickup_order, set_delivery_order, confirm_delivery_address or confirm_order - each item's lineItemId is how you refer to it; check customer.name/phone/address/apartmentUnit/notes and pickupTime here before asking the customer for them - never re-ask for something already set, and never guess a value that isn't; for delivery, check customer.addressConfirmed - if false, the address still needs to be read back and confirmed before checkout; check confirmation - if false, the order is not yet confirmed and must never be treated as final, even if it was confirmed earlier and has since changed):"
  $summaryHeading = "Concise order summary (use this, as-is or lightly reworded, whenever the customer asks what's in their order - don't recompute it from the raw JSON above):"
  $promotionsHeading = "Currently eligible active promotions (this list is already filtered to what's active AND eligible right now - you may only mention or apply a promotion from this exact list, by its id, via apply_promotion; never mention or apply any promotion not listed here, and never invent a discount):"
  $checkoutHeading = "Complete checkout summary (structured - items with quantities/customizations, fulfillment details, promotions and the full price breakdown; present this, as-is or lightly reworded, right before the customer checks out or whenever they want to review everything at once - don't assemble your own version):"
  return $systemPrompt + "`n`n" + $menuHeading + "`n" + $menuJson + "`n`n" + $orderHeading + "`n" + $orderJson + "`n`n" + $summaryHeading + "`n" + $orderSummary + "`n`n" + $promotionsHeading + "`n" + $promotionsSummary + "`n`n" + $checkoutHeading + "`n" + $checkoutSummary
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
    },
    @{
      type = "function"
      function = @{
        name = "confirm_delivery_address"
        description = "Mark the current delivery address as explicitly confirmed by the customer. Only call this AFTER you have read the full address back to them (street, apartment/unit if any) and they have explicitly said it's correct - never call it just because you set the address, and never call it if they asked for a correction (call set_delivery_order with the corrected address instead, then read it back and confirm again)."
        parameters = @{
          type = "object"
          properties = @{}
          required = @()
        }
      }
    },
    @{
      type = "function"
      function = @{
        name = "confirm_order"
        description = "Mark the order as confirmed by the customer - the gate that must happen before anything is ever treated as saved or final. Only call this AFTER presenting the complete checkout summary and receiving an explicit, unambiguous confirmation (e.g. 'yes, that's correct', 'confirm it', 'place the order'). A vague, hedging, or non-committal reply ('ok', 'sure', 'I guess', a question, or a reply that also asks for a change) does NOT count as confirmation - never call this on one of those; ask a direct yes/no question instead. Never call this preemptively or assume agreement."
        parameters = @{
          type = "object"
          properties = @{}
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

# Recomputes the full price breakdown from scratch every time: items
# total (menu unitPrice x quantity, already summed per line), minus any
# applied promotion discount, floored at 0, then flat tax and (delivery
# orders only) the flat delivery fee on top. Plain deterministic
# arithmetic - this is the only place order.total is ever set, so the
# model never calculates or states a total the backend didn't compute.
#
# Every order-mutating function calls this after making its change, so
# it also doubles as the one place that un-confirms a previously
# confirmed order: once anything changes, a prior confirm_order call no
# longer reflects what the customer actually agreed to, so it must be
# asked for again against the updated summary.
function Update-OrderTotal($order) {
  $itemsTotal = if ($order.items.Count -gt 0) { (($order.items | ForEach-Object { [double]$_.lineTotal }) | Measure-Object -Sum).Sum } else { 0 }
  $discount = if ($order.promotion) { [double]$order.promotion.discountAmount } else { 0 }
  # [math]::Max(0, ...) would resolve to the Int32 overload here (0 is an
  # int literal) and silently truncate the result to a whole number -
  # 0.0 forces the Double overload instead.
  $subtotal = [math]::Round([math]::Max(0.0, $itemsTotal - $discount), 2)
  $tax = [math]::Round($subtotal * ($script:TaxRatePercent / 100.0), 2)
  $deliveryFee = if ($order.orderType -eq "delivery") { $script:DeliveryFeeAmount } else { 0.0 }

  $order.subtotal = $subtotal
  $order.tax = $tax
  $order.deliveryFee = $deliveryFee
  $order.total = [math]::Round($subtotal + $tax + $deliveryFee, 2)

  if ($order.confirmation) {
    $order.confirmation = $false
    $order.status = "draft"
  }
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

  Update-OrderTotal $order

  return @{ ok = $true; orderType = $order.orderType; customerName = $order.customer.name; pickupTime = $order.pickupTime; total = $order.total }
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
    $newAddress = "$address".Trim()
    if ($newAddress -ne "$($order.customer.address)") {
      $order.customer.addressConfirmed = $false
    }
    $order.customer.address = $newAddress
  }
  if (-not [string]::IsNullOrWhiteSpace("$apartmentUnit")) {
    # apartment/unit is read back and confirmed as part of "the address"
    # (see the system prompt's address-confirmation section), so
    # changing it must invalidate a prior confirmation too, not just a
    # change to the street address.
    $newApartmentUnit = "$apartmentUnit".Trim()
    if ($newApartmentUnit -ne "$($order.customer.apartmentUnit)") {
      $order.customer.addressConfirmed = $false
    }
    $order.customer.apartmentUnit = $newApartmentUnit
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

  Update-OrderTotal $order

  return @{
    ok = $true
    orderType = $order.orderType
    customerName = $order.customer.name
    phone = $order.customer.phone
    address = $order.customer.address
    apartmentUnit = $order.customer.apartmentUnit
    instructions = $order.customer.notes
    addressConfirmed = $order.customer.addressConfirmed
    total = $order.total
  }
}

# Marks the current delivery address as explicitly confirmed by the
# customer - only valid once the order is actually a delivery order with
# an address on file. The model must have read the address back to the
# customer and gotten an explicit yes before calling this (enforced by
# the system prompt); this just makes that state durable. Any later
# change to the address via Set-DeliveryOrder resets this back to false.
function Confirm-DeliveryAddress($order) {
  if ($order.orderType -ne "delivery") {
    return @{ ok = $false; error = "This order isn't a delivery order, so there's no address to confirm." }
  }
  if ([string]::IsNullOrWhiteSpace("$($order.customer.address)")) {
    return @{ ok = $false; error = "No delivery address is on file yet - get one before confirming it." }
  }

  $order.customer.addressConfirmed = $true

  return @{ ok = $true; address = $order.customer.address; addressConfirmed = $true }
}

# The confirmation gate: marks order.confirmation true and order.status
# "confirmed", then saves the order to data/orders.json via
# Save-ConfirmedOrder - the only state this backend would ever treat as
# save/finalize-ready. Only valid once there's actually something
# complete to confirm: at least one item, a selected order type, the
# required customer details for it, and - for delivery - an address
# that's already been explicitly confirmed via confirm_delivery_address.
# This function only enforces those structural preconditions; judging
# whether the customer's reply was an unambiguous "yes" (as opposed to a
# vague or hedging one) is a language judgment the model has to make
# before ever calling this tool - see the system prompt. Update-
# OrderTotal resets confirmation back to false on any later change to
# the order, so a stale confirmation can never survive an edit and a
# draft can never reach Save-ConfirmedOrder.
function Confirm-Order($order, [string]$sessionId) {
  if ($order.confirmation) {
    # Already confirmed (and saved) earlier in this session with no
    # changes since - report the existing confirmation instead of
    # generating a second orderId/record for the same order.
    return @{ ok = $true; alreadyConfirmed = $true; confirmation = $true; status = $order.status; orderId = $order.orderId; total = $order.total }
  }

  if (-not $order.items -or $order.items.Count -eq 0) {
    return @{ ok = $false; error = "The order is empty - there's nothing to confirm yet." }
  }

  if ($order.orderType -eq "pickup") {
    if ([string]::IsNullOrWhiteSpace("$($order.customer.name)")) {
      return @{ ok = $false; error = "Pickup order is missing the customer's name - get it before confirming." }
    }
  } elseif ($order.orderType -eq "delivery") {
    $missing = @()
    if ([string]::IsNullOrWhiteSpace("$($order.customer.name)")) { $missing += "name" }
    if ([string]::IsNullOrWhiteSpace("$($order.customer.phone)")) { $missing += "phone" }
    if ([string]::IsNullOrWhiteSpace("$($order.customer.address)")) { $missing += "address" }
    if ($missing.Count -gt 0) {
      return @{ ok = $false; error = "Delivery order is missing required details: $($missing -join ', ') - get them before confirming."; missing = $missing }
    }
    if (-not $order.customer.addressConfirmed) {
      return @{ ok = $false; error = "The delivery address hasn't been confirmed yet - confirm it (confirm_delivery_address) before confirming the order." }
    }
  } else {
    return @{ ok = $false; error = "No fulfillment method has been selected yet - set pickup or delivery before confirming." }
  }

  $order.confirmation = $true
  $order.status = "confirmed"
  $order.orderId = [guid]::NewGuid().ToString()
  $order.confirmedAt = (Get-Date).ToUniversalTime().ToString("o")

  Save-ConfirmedOrder $order $sessionId

  return @{ ok = $true; confirmation = $true; status = $order.status; orderId = $order.orderId; total = $order.total }
}

# Appends one confirmed order to data/orders.json as a durable record -
# only ever called from Confirm-Order, after it has already verified the
# order is complete and set status to "confirmed", so a draft can never
# be saved here. Reads the existing array (starting fresh if the file is
# missing or empty), appends the new record, and writes the whole array
# back. -InputObject (not the pipeline) is required for ConvertTo-Json
# to keep wrapping the result in [ ] even when there's only one order.
function Save-ConfirmedOrder($order, [string]$sessionId) {
  $existingOrders = @()
  if (Test-Path $ordersPath) {
    $raw = Get-Content $ordersPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      # Assign to a variable before wrapping with @() - @() around the
      # ConvertFrom-Json pipeline directly double-wraps an empty JSON
      # array ("[]" -> a 1-element array whose element is itself an
      # empty array), because the pipeline emits that empty array as one
      # object. Wrapping an already-assigned array variable with @()
      # doesn't have that problem - it passes an existing array through
      # unchanged.
      $parsedOrders = $raw | ConvertFrom-Json
      $existingOrders = @($parsedOrders)
    }
  }

  $record = [ordered]@{
    orderId = $order.orderId
    sessionId = $sessionId
    status = $order.status
    confirmedAt = $order.confirmedAt
    items = $order.items
    orderType = $order.orderType
    customer = $order.customer
    pickupTime = $order.pickupTime
    promotion = $order.promotion
    subtotal = $order.subtotal
    tax = $order.tax
    deliveryFee = $order.deliveryFee
    total = $order.total
  }

  $existingOrders = @($existingOrders) + $record
  ConvertTo-Json -InputObject $existingOrders -Depth 10 | Set-Content -Path $ordersPath -Encoding UTF8
}

# Reads every saved order back out of data/orders.json for the staff
# dashboard - same empty/missing-file handling and the same
# assign-before-wrap fix as Save-ConfirmedOrder (see the comment there),
# so an empty file correctly comes back as an empty array, not a
# 1-element array containing an empty array.
function Get-SavedOrders {
  if (-not (Test-Path $ordersPath)) { return @() }
  $raw = Get-Content $ordersPath -Raw
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  $parsedOrders = $raw | ConvertFrom-Json
  return @($parsedOrders)
}

# Changes one saved order's status (the only thing the staff dashboard
# can edit) - validates the orderId exists and the status is one of
# $script:OrderStatuses, then rewrites the whole file. PSCustomObjects
# from ConvertFrom-Json are reference types, so updating the matched
# order's .status property updates it in place within $orders.
function Update-SavedOrderStatus([string]$orderId, [string]$status) {
  if ([string]::IsNullOrWhiteSpace($orderId)) {
    return @{ ok = $false; error = "Missing orderId." }
  }
  if ($script:OrderStatuses -notcontains $status) {
    return @{ ok = $false; error = "Invalid status '$status'. Must be one of: $($script:OrderStatuses -join ', ')." }
  }

  $orders = Get-SavedOrders
  $target = $orders | Where-Object { $_.orderId -eq $orderId } | Select-Object -First 1
  if (-not $target) {
    return @{ ok = $false; error = "No saved order with id '$orderId'." }
  }

  $target.status = $status
  ConvertTo-Json -InputObject $orders -Depth 10 | Set-Content -Path $ordersPath -Encoding UTF8

  return @{ ok = $true; orderId = $orderId; status = $status }
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
Write-Host "Staff dashboard at http://localhost:$Port/dashboard"

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $req = $context.Request
  $res = $context.Response
  $res.ContentType = "application/json"

  try {
    if ($req.HttpMethod -eq "GET" -and $req.Url.AbsolutePath -eq "/dashboard") {
      $res.ContentType = "text/html"
      $html = Get-Content $dashboardPath -Raw
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } elseif ($req.HttpMethod -eq "GET" -and $req.Url.AbsolutePath -eq "/api/orders") {
      # @() wraps the call itself (not a variable assigned from it) -
      # otherwise a zero-order result collapses to nothing at all
      # (PowerShell functions returning an empty array emit zero
      # pipeline objects), and ConvertTo-Json on that produces an empty
      # response body instead of "[]".
      $json = ConvertTo-Json -InputObject @(Get-SavedOrders) -Depth 10
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } elseif ($req.HttpMethod -eq "POST" -and $req.Url.AbsolutePath -eq "/api/orders/status") {
      $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
      $bodyText = $reader.ReadToEnd()
      $payload = $bodyText | ConvertFrom-Json
      $result = Update-SavedOrderStatus "$($payload.orderId)" "$($payload.status)"
      if (-not $result.ok) { $res.StatusCode = 400 }
      $json = $result | ConvertTo-Json -Depth 10
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } elseif ($req.HttpMethod -ne "POST" -or $req.Url.AbsolutePath -ne "/api/chat") {
      $res.StatusCode = 404
      $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Not found. POST /api/chat, GET /dashboard, GET /api/orders, POST /api/orders/status."}')
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
            # A plain if statement, not "$x = if (...) {...} else {...}" -
            # assigning the result of an if/else expression collapses an
            # explicitly-empty array (selectedOptionIds: []) to $null,
            # making it indistinguishable from the field being omitted
            # entirely (same PowerShell empty-array-collapse gotcha as
            # elsewhere in this file - see Save-ConfirmedOrder).
            $optionIds = $null
            if ($null -ne $args.selectedOptionIds) {
              $optionIds = @($args.selectedOptionIds)
            }
            $result = Update-OrderItem $session.Order $menu $args.lineItemId $args.quantity $optionIds
          } elseif ($toolCall.function.name -eq "remove_order_item") {
            $result = Remove-OrderItem $session.Order $args.lineItemId $args.quantity
          } elseif ($toolCall.function.name -eq "apply_promotion") {
            $result = Apply-Promotion $session.Order $menu $promotions $args.promotionId $now
          } elseif ($toolCall.function.name -eq "set_pickup_order") {
            $result = Set-PickupOrder $session.Order $args.customerName $args.pickupTime
          } elseif ($toolCall.function.name -eq "set_delivery_order") {
            $result = Set-DeliveryOrder $session.Order $args.customerName $args.phone $args.address $args.apartmentUnit $args.instructions
          } elseif ($toolCall.function.name -eq "confirm_delivery_address") {
            $result = Confirm-DeliveryAddress $session.Order
          } elseif ($toolCall.function.name -eq "confirm_order") {
            $result = Confirm-Order $session.Order $session.SessionId
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
