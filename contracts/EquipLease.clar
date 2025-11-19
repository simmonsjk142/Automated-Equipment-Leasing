;; title: EquipLease
;; version: 1.0.0
;; summary: Automated Equipment Leasing Smart Contract
;; description: A trustless system for leasing agricultural equipment with automated payments and dispute resolution

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PARAMS (err u103))
(define-constant ERR-LEASE-ACTIVE (err u104))
(define-constant ERR-LEASE-INACTIVE (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-LEASE-EXPIRED (err u107))
(define-constant ERR-EQUIPMENT-NOT-AVAILABLE (err u108))
(define-constant ERR-INVALID-STATUS (err u109))
(define-constant ERR-PAYMENT-OVERDUE (err u110))
(define-constant ERR-DISPUTE-NOT-FOUND (err u111))
(define-constant ERR-DISPUTE-ALREADY-EXISTS (err u112))
(define-constant ERR-DISPUTE-ALREADY-RESOLVED (err u113))
(define-constant ERR-DISPUTE-NOT-EXPIRED (err u114))
(define-constant ERR-INVALID-DISPUTE-PARTY (err u115))
(define-constant ERR-INSURANCE-NOT-ACTIVE (err u116))
(define-constant ERR-CLAIM-NOT-FOUND (err u117))
(define-constant ERR-INVALID-CLAIM-SEVERITY (err u118))
(define-constant ERR-INSUFFICIENT-ESCROW (err u119))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-RATE u5)

(define-data-var next-equipment-id uint u1)
(define-data-var next-lease-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var platform-balance uint u0)

(define-map equipment
  { equipment-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    description: (string-ascii 200),
    daily-rate: uint,
    deposit-required: uint,
    available: bool,
    total-leases: uint,
    created-at: uint
  })

(define-map leases
  { lease-id: uint }
  {
    equipment-id: uint,
    lessor: principal,
    lessee: principal,
    start-block: uint,
    end-block: uint,
    daily-rate: uint,
    deposit-paid: uint,
    total-cost: uint,
    status: (string-ascii 20),
    created-at: uint,
    last-payment-block: uint
  })

(define-map user-equipment
  { owner: principal, equipment-id: uint }
  { registered: bool })

(define-map user-leases
  { user: principal, lease-id: uint }
  { active: bool })

(define-map equipment-ratings
  { equipment-id: uint }
  {
    total-rating: uint,
    rating-count: uint,
    average-rating: uint
  })

(define-map disputes
  { dispute-id: uint }
  {
    lease-id: uint,
    initiator: principal,
    opponent: principal,
    status: (string-ascii 20),
    reason: (string-ascii 100),
    created-block: uint,
    resolved-block: uint,
    winner: (optional principal)
  })

(define-map lease-disputes
  { lease-id: uint }
  { dispute-id: uint })

(define-map equipment-insurance
  { equipment-id: uint }
  { escrow-balance: uint })

(define-map lease-insurance
  { lease-id: uint }
  { active: bool })

(define-map damage-claims
  { claim-id: uint }
  {
    lessor: principal,
    lessee: principal,
    equipment-id: uint,
    lease-id: uint,
    severity: uint,
    amount: uint,
    status: (string-ascii 20),
    created-block: uint
  })

(define-public (register-equipment (name (string-ascii 50)) (description (string-ascii 200)) (daily-rate uint) (deposit-required uint))
  (let ((equipment-id (var-get next-equipment-id)))
    (asserts! (> daily-rate u0) ERR-INVALID-PARAMS)
    (asserts! (> deposit-required u0) ERR-INVALID-PARAMS)
    (asserts! (> (len name) u0) ERR-INVALID-PARAMS)
    
    (map-set equipment
      { equipment-id: equipment-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        daily-rate: daily-rate,
        deposit-required: deposit-required,
        available: true,
        total-leases: u0,
        created-at: stacks-block-height
      })
    
    (map-set user-equipment
      { owner: tx-sender, equipment-id: equipment-id }
      { registered: true })
    
    (var-set next-equipment-id (+ equipment-id u1))
    (ok equipment-id)))

(define-public (create-lease (equipment-id uint) (duration-blocks uint))
  (let (
    (lease-id (var-get next-lease-id))
    (equipment-data (unwrap! (map-get? equipment { equipment-id: equipment-id }) ERR-NOT-FOUND))
    (daily-rate (get daily-rate equipment-data))
    (deposit (get deposit-required equipment-data))
    (days (/ duration-blocks u144))
    (total-cost (+ (* daily-rate days) deposit))
    (platform-fee (/ (* total-cost PLATFORM-FEE-RATE) u100))
    (lessor-payment (- total-cost platform-fee))
  )
    (asserts! (get available equipment-data) ERR-EQUIPMENT-NOT-AVAILABLE)
    (asserts! (> duration-blocks u0) ERR-INVALID-PARAMS)
    (asserts! (not (is-eq tx-sender (get owner equipment-data))) ERR-NOT-AUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) total-cost) ERR-INSUFFICIENT-FUNDS)
    
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    
    (map-set leases
      { lease-id: lease-id }
      {
        equipment-id: equipment-id,
        lessor: (get owner equipment-data),
        lessee: tx-sender,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height duration-blocks),
        daily-rate: daily-rate,
        deposit-paid: deposit,
        total-cost: total-cost,
        status: "active",
        created-at: stacks-block-height,
        last-payment-block: stacks-block-height
      })
    
    (map-set user-leases
      { user: tx-sender, lease-id: lease-id }
      { active: true })
    
    (map-set equipment
      { equipment-id: equipment-id }
      (merge equipment-data { available: false, total-leases: (+ (get total-leases equipment-data) u1) }))
    
    (var-set next-lease-id (+ lease-id u1))
    (var-set platform-balance (+ (var-get platform-balance) platform-fee))
    
    (ok lease-id)))

(define-public (complete-lease (lease-id uint) (condition-rating uint))
  (let (
    (lease-data (unwrap! (map-get? leases { lease-id: lease-id }) ERR-NOT-FOUND))
    (equipment-id (get equipment-id lease-data))
    (equipment-data (unwrap! (map-get? equipment { equipment-id: equipment-id }) ERR-NOT-FOUND))
    (deposit (get deposit-paid lease-data))
    (lessor (get lessor lease-data))
    (daily-rate (get daily-rate lease-data))
    (total-lease-cost (- (get total-cost lease-data) deposit))
  )
    (asserts! (is-eq tx-sender (get lessee lease-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status lease-data) "active") ERR-LEASE-INACTIVE)
    (asserts! (is-none (map-get? lease-disputes { lease-id: lease-id })) ERR-INVALID-STATUS)
    (asserts! (<= condition-rating u5) ERR-INVALID-PARAMS)
    (asserts! (>= condition-rating u1) ERR-INVALID-PARAMS)
    
    (let ((deposit-return (if (>= condition-rating u4) deposit (/ deposit u2))))
      (try! (as-contract (stx-transfer? total-lease-cost tx-sender lessor)))
      (try! (as-contract (stx-transfer? deposit-return tx-sender (get lessee lease-data))))
      
      (map-set leases
        { lease-id: lease-id }
        (merge lease-data { status: "completed" }))
      
      (map-set equipment
        { equipment-id: equipment-id }
        (merge equipment-data { available: true }))
      
      (map-set user-leases
        { user: (get lessee lease-data), lease-id: lease-id }
        { active: false })
      
      (unwrap-panic (update-equipment-rating equipment-id condition-rating))
      (ok true))))

(define-public (cancel-lease (lease-id uint))
  (let (
    (lease-data (unwrap! (map-get? leases { lease-id: lease-id }) ERR-NOT-FOUND))
    (equipment-id (get equipment-id lease-data))
    (equipment-data (unwrap! (map-get? equipment { equipment-id: equipment-id }) ERR-NOT-FOUND))
    (refund-amount (/ (get total-cost lease-data) u2))
  )
    (asserts! (is-eq tx-sender (get lessee lease-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status lease-data) "active") ERR-LEASE-INACTIVE)
    (asserts! (is-none (map-get? lease-disputes { lease-id: lease-id })) ERR-INVALID-STATUS)
    (asserts! (< stacks-block-height (+ (get start-block lease-data) u144)) ERR-NOT-AUTHORIZED)
    
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get lessee lease-data))))
    
    (map-set leases
      { lease-id: lease-id }
      (merge lease-data { status: "cancelled" }))
    
    (map-set equipment
      { equipment-id: equipment-id }
      (merge equipment-data { available: true }))
    
    (map-set user-leases
      { user: (get lessee lease-data), lease-id: lease-id }
      { active: false })
    
    (ok true)))

(define-public (update-equipment-availability (equipment-id uint) (available bool))
  (let ((equipment-data (unwrap! (map-get? equipment { equipment-id: equipment-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get owner equipment-data)) ERR-NOT-AUTHORIZED)
    
    (map-set equipment
      { equipment-id: equipment-id }
      (merge equipment-data { available: available }))
    
    (ok true)))

(define-public (update-equipment-rates (equipment-id uint) (new-daily-rate uint) (new-deposit uint))
  (let ((equipment-data (unwrap! (map-get? equipment { equipment-id: equipment-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get owner equipment-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> new-daily-rate u0) ERR-INVALID-PARAMS)
    (asserts! (> new-deposit u0) ERR-INVALID-PARAMS)
    
    (map-set equipment
      { equipment-id: equipment-id }
      (merge equipment-data { daily-rate: new-daily-rate, deposit-required: new-deposit }))
    
    (ok true)))

(define-public (withdraw-platform-fees)
  (let ((balance (var-get platform-balance)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> balance u0) ERR-INSUFFICIENT-FUNDS)
    
    (try! (as-contract (stx-transfer? balance tx-sender CONTRACT-OWNER)))
    (var-set platform-balance u0)
    
    (ok balance)))

(define-public (file-dispute (lease-id uint) (reason (string-ascii 100)))
  (let
    (
      (lease-data (unwrap! (map-get? leases { lease-id: lease-id }) ERR-NOT-FOUND))
      (caller tx-sender)
      (dispute-id (var-get next-dispute-id))
      (existing-dispute (map-get? lease-disputes { lease-id: lease-id }))
    )
    (asserts! (is-eq (get status lease-data) "active") ERR-LEASE-INACTIVE)
    (asserts! (is-none existing-dispute) ERR-DISPUTE-ALREADY-EXISTS)
    (asserts! (or (is-eq caller (get lessor lease-data)) (is-eq caller (get lessee lease-data))) ERR-INVALID-DISPUTE-PARTY)
    
    (let
      (
        (opponent (if (is-eq caller (get lessor lease-data)) (get lessee lease-data) (get lessor lease-data)))
      )
      (map-set disputes
        { dispute-id: dispute-id }
        {
          lease-id: lease-id,
          initiator: caller,
          opponent: opponent,
          status: "pending",
          reason: reason,
          created-block: stacks-block-height,
          resolved-block: u0,
          winner: none
        }
      )
      (map-set lease-disputes
        { lease-id: lease-id }
        { dispute-id: dispute-id }
      )
      (var-set next-dispute-id (+ dispute-id u1))
      (ok dispute-id)
    )
  )
)

(define-public (resolve-dispute (dispute-id uint) (winner principal))
  (let
    (
      (dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-DISPUTE-NOT-FOUND))
      (lease-data (unwrap! (map-get? leases { lease-id: (get lease-id dispute-data) }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq (get status dispute-data) "pending") ERR-DISPUTE-ALREADY-RESOLVED)
    (asserts! (or (is-eq winner (get initiator dispute-data)) (is-eq winner (get opponent dispute-data))) ERR-INVALID-DISPUTE-PARTY)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (let
      (
        (winner-status (if (is-eq winner (get lessor lease-data)) "lessor-win" "lessee-win"))
        (dispute-funds (get total-cost lease-data))
      )
      (map-set disputes
        { dispute-id: dispute-id }
        (merge dispute-data {
          status: winner-status,
          resolved-block: stacks-block-height,
          winner: (some winner)
        })
      )
      (map-delete lease-disputes { lease-id: (get lease-id dispute-data) })
      
      (try! (as-contract (stx-transfer? dispute-funds tx-sender winner)))
      (ok true)
    )
  )
)

(define-public (auto-expire-dispute (dispute-id uint))
  (let
    (
      (dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-DISPUTE-NOT-FOUND))
      (lease-data (unwrap! (map-get? leases { lease-id: (get lease-id dispute-data) }) ERR-NOT-FOUND))
      (blocks-passed (- stacks-block-height (get created-block dispute-data)))
    )
    (asserts! (is-eq (get status dispute-data) "pending") ERR-DISPUTE-ALREADY-RESOLVED)
    (asserts! (>= blocks-passed u72) ERR-DISPUTE-NOT-EXPIRED)
    
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute-data {
        status: "expired",
        resolved-block: stacks-block-height,
        winner: none
      })
    )
    (map-delete lease-disputes { lease-id: (get lease-id dispute-data) })
    
    (let
      (
        (dispute-funds (get total-cost lease-data))
        (half-payment (/ dispute-funds u2))
      )
      (try! (as-contract (stx-transfer? half-payment tx-sender (get lessor lease-data))))
      (try! (as-contract (stx-transfer? half-payment tx-sender (get lessee lease-data))))
      (ok true)
    )
  )
)

(define-private (update-equipment-rating (equipment-id uint) (rating uint))
  (let (
    (current-rating (default-to { total-rating: u0, rating-count: u0, average-rating: u0 }
      (map-get? equipment-ratings { equipment-id: equipment-id })))
    (new-total (+ (get total-rating current-rating) rating))
    (new-count (+ (get rating-count current-rating) u1))
    (new-average (/ new-total new-count))
  )
    (map-set equipment-ratings
      { equipment-id: equipment-id }
      {
        total-rating: new-total,
        rating-count: new-count,
        average-rating: new-average
      })
    (ok true)))

(define-public (enable-insurance (lease-id uint))
  (let (
    (lease-data (unwrap! (map-get? leases { lease-id: lease-id }) ERR-NOT-FOUND))
    (equipment-id (get equipment-id lease-data))
    (premium (/ (get total-cost lease-data) u10))
    (current-escrow (default-to { escrow-balance: u0 }
      (map-get? equipment-insurance { equipment-id: equipment-id })))
  )
    (asserts! (is-eq tx-sender (get lessee lease-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status lease-data) "active") ERR-LEASE-INACTIVE)
    (asserts! (is-none (map-get? lease-insurance { lease-id: lease-id })) ERR-ALREADY-EXISTS)
    (asserts! (>= (stx-get-balance tx-sender) premium) ERR-INSUFFICIENT-FUNDS)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (map-set equipment-insurance
      { equipment-id: equipment-id }
      { escrow-balance: (+ (get escrow-balance current-escrow) premium) })
    
    (map-set lease-insurance
      { lease-id: lease-id }
      { active: true })
    
    (ok true)))

(define-public (file-damage-claim (lease-id uint) (severity uint) (amount uint))
  (let (
    (lease-data (unwrap! (map-get? leases { lease-id: lease-id }) ERR-NOT-FOUND))
    (equipment-id (get equipment-id lease-data))
    (claim-id (var-get next-claim-id))
    (caller tx-sender)
  )
    (asserts! (is-some (map-get? lease-insurance { lease-id: lease-id })) ERR-INSURANCE-NOT-ACTIVE)
    (asserts! (or (is-eq caller (get lessor lease-data)) (is-eq caller (get lessee lease-data))) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= severity u1) (<= severity u3)) ERR-INVALID-CLAIM-SEVERITY)
    (asserts! (> amount u0) ERR-INVALID-PARAMS)
    
    (let
      (
        (opponent (if (is-eq caller (get lessor lease-data)) (get lessee lease-data) (get lessor lease-data)))
      )
      (map-set damage-claims
        { claim-id: claim-id }
        {
          lessor: (get lessor lease-data),
          lessee: (get lessee lease-data),
          equipment-id: equipment-id,
          lease-id: lease-id,
          severity: severity,
          amount: amount,
          status: "pending",
          created-block: stacks-block-height
        }
      )
      (var-set next-claim-id (+ claim-id u1))
      (ok claim-id)
    )
  )
)

(define-public (resolve-damage-claim (claim-id uint) (approved bool))
  (let (
    (claim-data (unwrap! (map-get? damage-claims { claim-id: claim-id }) ERR-CLAIM-NOT-FOUND))
    (equipment-id (get equipment-id claim-data))
    (escrow-data (unwrap! (map-get? equipment-insurance { equipment-id: equipment-id }) ERR-INSUFFICIENT-ESCROW))
    (lessor (get lessor claim-data))
    (lessee (get lessee claim-data))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status claim-data) "pending") ERR-INVALID-STATUS)
    
    (if approved
      (let (
        (payout (if (> (get amount claim-data) (get escrow-balance escrow-data))
                   (get escrow-balance escrow-data)
                   (get amount claim-data)))
      )
        (try! (as-contract (stx-transfer? payout tx-sender lessor)))
        (map-set equipment-insurance
          { equipment-id: equipment-id }
          { escrow-balance: (- (get escrow-balance escrow-data) payout) })
      )
      (try! (as-contract (stx-transfer? (get amount claim-data) tx-sender lessee)))
    )
    
    (map-set damage-claims
      { claim-id: claim-id }
      (merge claim-data { status: "resolved" }))
    
    (ok true)
  )
)

(define-public (withdraw-insurance-balance (equipment-id uint))
  (let ((escrow-data (unwrap! (map-get? equipment-insurance { equipment-id: equipment-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (get escrow-balance escrow-data) u0) ERR-INSUFFICIENT-FUNDS)
    
    (let ((balance (get escrow-balance escrow-data)))
      (try! (as-contract (stx-transfer? balance tx-sender CONTRACT-OWNER)))
      (map-set equipment-insurance
        { equipment-id: equipment-id }
        { escrow-balance: u0 })
      (ok balance)
    )
  )
)

(define-read-only (get-equipment (equipment-id uint))
  (map-get? equipment { equipment-id: equipment-id }))

(define-read-only (get-lease (lease-id uint))
  (map-get? leases { lease-id: lease-id }))

(define-read-only (get-equipment-rating (equipment-id uint))
  (map-get? equipment-ratings { equipment-id: equipment-id }))

(define-read-only (is-lease-expired (lease-id uint))
  (match (map-get? leases { lease-id: lease-id })
    lease-data (> stacks-block-height (get end-block lease-data))
    false))

(define-read-only (get-lease-time-remaining (lease-id uint))
  (match (map-get? leases { lease-id: lease-id })
    lease-data (if (> (get end-block lease-data) stacks-block-height)
                   (some (- (get end-block lease-data) stacks-block-height))
                   (some u0))
    none))

(define-read-only (calculate-lease-cost (equipment-id uint) (duration-blocks uint))
  (match (map-get? equipment { equipment-id: equipment-id })
    equipment-data 
      (let (
        (daily-rate (get daily-rate equipment-data))
        (deposit (get deposit-required equipment-data))
        (days (/ duration-blocks u144))
        (total (+ (* daily-rate days) deposit))
        (platform-fee (/ (* total PLATFORM-FEE-RATE) u100))
      )
        (ok { total-cost: total, platform-fee: platform-fee, lessor-receives: (- total platform-fee) }))
    ERR-NOT-FOUND))

(define-read-only (get-user-equipment-count (owner principal))
  (let ((equipment-id (var-get next-equipment-id)))
    (fold count-user-equipment (list equipment-id) u0)))

(define-private (count-user-equipment (equipment-id uint) (count uint))
  (match (map-get? equipment { equipment-id: equipment-id })
    equipment-data (if (is-eq (get owner equipment-data) tx-sender) (+ count u1) count)
    count))

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id }))

(define-read-only (is-dispute-active (lease-id uint))
  (match (map-get? lease-disputes { lease-id: lease-id })
    dispute-id-data
    (match (map-get? disputes { dispute-id: (get dispute-id dispute-id-data) })
      dispute-data
      (is-eq (get status dispute-data) "pending")
      false
    )
    false
  )
)

(define-read-only (get-dispute-time-remaining (dispute-id uint))
  (match (map-get? disputes { dispute-id: dispute-id })
    dispute-data
    (let
      (
        (blocks-passed (- stacks-block-height (get created-block dispute-data)))
        (blocks-remaining (if (< blocks-passed u72) (- u72 blocks-passed) u0))
      )
      (ok blocks-remaining)
    )
    (err ERR-DISPUTE-NOT-FOUND)
  )
)

(define-read-only (get-platform-stats)
  {
    total-equipment: (- (var-get next-equipment-id) u1),
    total-leases: (- (var-get next-lease-id) u1),
    total-disputes: (- (var-get next-dispute-id) u1),
    platform-balance: (var-get platform-balance),
    platform-fee-rate: PLATFORM-FEE-RATE
  })

(define-read-only (get-insurance-status (lease-id uint))
  (map-get? lease-insurance { lease-id: lease-id }))

(define-read-only (get-escrow-balance (equipment-id uint))
  (map-get? equipment-insurance { equipment-id: equipment-id }))

(define-read-only (get-damage-claim (claim-id uint))
  (map-get? damage-claims { claim-id: claim-id }))

(define-read-only (calculate-insurance-premium (total-lease-cost uint))
  (ok (/ total-lease-cost u10)))
