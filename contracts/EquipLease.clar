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

(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-RATE u5)

(define-data-var next-equipment-id uint u1)
(define-data-var next-lease-id uint u1)
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

(define-read-only (get-platform-stats)
  {
    total-equipment: (- (var-get next-equipment-id) u1),
    total-leases: (- (var-get next-lease-id) u1),
    platform-balance: (var-get platform-balance),
    platform-fee-rate: PLATFORM-FEE-RATE
  })
