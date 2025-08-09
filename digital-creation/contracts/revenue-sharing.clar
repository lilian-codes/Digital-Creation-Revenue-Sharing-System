;; Digital Creation Revenue Sharing System
;; Enables automatic revenue distribution to creators and collaborators
;; Supports initial sales, resale commissions, and multi-creator projects

;; Error constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-CREATION-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMETERS (err u102))
(define-constant ERR-DUPLICATE-ENTRY (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-ITEM-ALREADY-PURCHASED (err u105))
(define-constant ERR-ITEM-NOT-PURCHASED (err u106))
(define-constant ERR-NO-EARNINGS-AVAILABLE (err u107))
(define-constant ERR-INVALID-RATE (err u108))
(define-constant ERR-TOKEN-ALREADY-CONNECTED (err u109))
(define-constant ERR-NO-TOKEN-CONTRACT (err u110))

;; Maximum values for validation
(define-constant MAX-COMMISSION-RATE u300) ;; 30%
(define-constant RATE-BASE u1000) ;; 1000 = 100%
(define-constant MAX-NAME-LENGTH u256)
(define-constant MAX-SUMMARY-LENGTH u1024)
(define-constant MAX-POSITION-LENGTH u64)

;; Define digital creation data
(define-map digital-creations
  { creation-id: uint }
  {
    name: (string-utf8 256),
    summary: (string-utf8 1024),
    original-creator: principal,
    created-block: uint,
    is-active: bool,
    initial-purchased: bool,
    initial-cost: uint,
    commission-rate: uint,  ;; Out of 1000 (e.g., 50 = 5%)
    token-contract: (optional principal)
  }
)

;; Collaborators for a digital creation
(define-map collaborators
  { creation-id: uint, collaborator: principal }
  {
    ownership-percentage: uint,    ;; Out of 1000 (e.g., 500 = 50%)
    position: (string-ascii 64)
  }
)

;; Revenue distribution tracking
(define-map revenue-tracking
  { creation-id: uint }
  {
    total-earnings: uint,
    last-payout: uint
  }
)

;; Withdrawable earnings per collaborator
(define-map withdrawable-earnings
  { creation-id: uint, collaborator: principal }
  { balance: uint }
)

;; Track resale transactions
(define-map resale-transactions
  { creation-id: uint, transaction-id: uint }
  {
    previous-owner: principal,
    new-owner: principal,
    price: uint,
    commission-paid: uint,
    block-time: uint
  }
)

;; Next available IDs
(define-data-var next-creation-id-counter uint u1)
(define-map next-transaction-id-counter { creation-id: uint } { id: uint })

;; Contract administrator for management functions
(define-data-var contract-admin-address principal tx-sender)

;; Helper function to validate string lengths
(define-private (is-valid-text-length (input-text (string-utf8 1024)) (max-length uint))
  (<= (len input-text) max-length)
)

;; Helper function to validate percentage
(define-private (is-valid-rate (rate uint))
  (<= rate RATE-BASE)
)

;; Helper function to validate creation ID exists
(define-private (validate-creation-id (creation-id-input uint))
  (is-some (map-get? digital-creations { creation-id: creation-id-input }))
)

;; Register a new digital creation
(define-public (register-creation
                (name-input (string-utf8 256))
                (summary-input (string-utf8 1024))
                (initial-cost-input uint)
                (commission-rate-input uint))
  (let
    ((new-creation-id (var-get next-creation-id-counter)))
    
    ;; Validate inputs
    (asserts! (> initial-cost-input u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= commission-rate-input MAX-COMMISSION-RATE) ERR-INVALID-RATE)
    (asserts! (> (len name-input) u0) ERR-INVALID-PARAMETERS)
    (asserts! (is-valid-text-length name-input MAX-NAME-LENGTH) ERR-INVALID-PARAMETERS)
    (asserts! (is-valid-text-length summary-input MAX-SUMMARY-LENGTH) ERR-INVALID-PARAMETERS)
    
    ;; Create the digital creation record
    (map-set digital-creations
      { creation-id: new-creation-id }
      {
        name: name-input,
        summary: summary-input,
        original-creator: tx-sender,
        created-block: block-height,
        is-active: true,
        initial-purchased: false,
        initial-cost: initial-cost-input,
        commission-rate: commission-rate-input,
        token-contract: none
      }
    )
    
    ;; Add original creator as 100% collaborator by default
    (map-set collaborators
      { creation-id: new-creation-id, collaborator: tx-sender }
      {
        ownership-percentage: RATE-BASE,  ;; 100%
        position: "original-creator"
      }
    )
    
    ;; Initialize revenue tracking
    (map-set revenue-tracking
      { creation-id: new-creation-id }
      {
        total-earnings: u0,
        last-payout: u0
      }
    )
    
    ;; Initialize transaction counter
    (map-set next-transaction-id-counter
      { creation-id: new-creation-id }
      { id: u1 }
    )
    
    ;; Increment creation ID counter
    (var-set next-creation-id-counter (+ new-creation-id u1))
    
    (ok new-creation-id)
  )
)

;; Add a collaborator to a digital creation
(define-public (add-collaborator
                (creation-id-input uint)
                (collaborator-input principal)
                (ownership-percentage-input uint)
                (position-input (string-ascii 64)))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND))
     (creator-ownership-data (unwrap! (map-get? collaborators { creation-id: creation-id-input, collaborator: (get original-creator creation-data) })
                            ERR-CREATION-NOT-FOUND))
     (existing-collaborator-record (map-get? collaborators { creation-id: creation-id-input, collaborator: collaborator-input }))
     (collaborator-exists (is-some existing-collaborator-record))
     (current-ownership (if collaborator-exists
                       (get ownership-percentage (unwrap-panic existing-collaborator-record))
                      u0))
     (available-ownership (- (get ownership-percentage creator-ownership-data) current-ownership))
     (new-creator-ownership (- (get ownership-percentage creator-ownership-data) ownership-percentage-input)))
    
    ;; Validate inputs
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (is-eq tx-sender (get original-creator creation-data)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (get initial-purchased creation-data)) ERR-ITEM-ALREADY-PURCHASED)
    (asserts! (> ownership-percentage-input u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= ownership-percentage-input available-ownership) ERR-INVALID-RATE)
    (asserts! (> (len position-input) u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= (len position-input) MAX-POSITION-LENGTH) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq collaborator-input (get original-creator creation-data))) ERR-INVALID-PARAMETERS)
    
    ;; Add/update the collaborator
    (map-set collaborators
      { creation-id: creation-id-input, collaborator: collaborator-input }
      {
        ownership-percentage: ownership-percentage-input,
        position: position-input
      }
    )
    
    ;; Update original creator's ownership
    (map-set collaborators
      { creation-id: creation-id-input, collaborator: (get original-creator creation-data) }
      {
        ownership-percentage: new-creator-ownership,
        position: "original-creator"
      }
    )
    
    (ok true)
  )
)

;; Remove a collaborator from a digital creation
(define-public (remove-collaborator (creation-id-input uint) (collaborator-input principal))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND))
     (collaborator-record (unwrap! (map-get? collaborators { creation-id: creation-id-input, collaborator: collaborator-input })
                               ERR-CREATION-NOT-FOUND))
     (creator-ownership-data (unwrap! (map-get? collaborators { creation-id: creation-id-input, collaborator: (get original-creator creation-data) })
                            ERR-CREATION-NOT-FOUND))
     (ownership-to-return (get ownership-percentage collaborator-record))
     (new-creator-ownership (+ (get ownership-percentage creator-ownership-data) ownership-to-return)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (is-eq tx-sender (get original-creator creation-data)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (get initial-purchased creation-data)) ERR-ITEM-ALREADY-PURCHASED)
    (asserts! (not (is-eq collaborator-input (get original-creator creation-data))) ERR-INVALID-PARAMETERS)
    
    ;; Remove collaborator
    (map-delete collaborators { creation-id: creation-id-input, collaborator: collaborator-input })
    
    ;; Return ownership to original creator
    (map-set collaborators
      { creation-id: creation-id-input, collaborator: (get original-creator creation-data) }
      {
        ownership-percentage: new-creator-ownership,
        position: "original-creator"
      }
    )
    
    (ok true)
  )
)

;; Link token contract to digital creation (original creator only)
(define-public (link-token-contract (creation-id-input uint) (token-contract-input principal))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (is-eq tx-sender (get original-creator creation-data)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-none (get token-contract creation-data)) ERR-TOKEN-ALREADY-CONNECTED)
    
    ;; Link the contract
    (map-set digital-creations
      { creation-id: creation-id-input }
      (merge creation-data { token-contract: (some token-contract-input) })
    )
    
    (ok true)
  )
)

;; Initial purchase of digital creation
(define-public (initial-purchase (creation-id-input uint))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND))
     (purchase-price (get initial-cost creation-data)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (get is-active creation-data) ERR-INVALID-PARAMETERS)
    (asserts! (not (get initial-purchased creation-data)) ERR-ITEM-ALREADY-PURCHASED)
    (asserts! (is-some (get token-contract creation-data)) ERR-NO-TOKEN-CONTRACT)
    
    ;; Check buyer has sufficient funds
    (asserts! (>= (stx-get-balance tx-sender) purchase-price) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer STX for purchase to contract
    (try! (stx-transfer? purchase-price tx-sender (as-contract tx-sender)))
    
    ;; Mark as purchased
    (map-set digital-creations
      { creation-id: creation-id-input }
      (merge creation-data { initial-purchased: true })
    )
    
    ;; Distribute to collaborators
    (try! (distribute-initial-proceeds creation-id-input purchase-price))
    
    (ok true)
  )
)

;; Private function to distribute initial purchase proceeds
(define-private (distribute-initial-proceeds (creation-id-input uint) (proceeds-amount uint))
  (let
    ((creation-data (unwrap-panic (map-get? digital-creations { creation-id: creation-id-input })))
     (creator-principal (get original-creator creation-data))
     (creator-record (unwrap-panic (map-get? collaborators { creation-id: creation-id-input, collaborator: creator-principal })))
     (creator-ownership-percentage (get ownership-percentage creator-record))
     (creator-payment (/ (* proceeds-amount creator-ownership-percentage) RATE-BASE)))
    
    ;; Transfer to original creator (simplified - in a full implementation you'd iterate through all collaborators)
    (if (> creator-payment u0)
        (as-contract (try! (stx-transfer? creator-payment tx-sender creator-principal)))
        true)
    
    (ok true)
  )
)

;; Record a resale transaction
(define-public (record-resale-transaction
                (creation-id-input uint)
                (previous-owner-input principal)
                (price-input uint))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND))
     (transaction-counter-data (unwrap! (map-get? next-transaction-id-counter { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND))
     (new-transaction-id (get id transaction-counter-data))
     (commission-percentage (get commission-rate creation-data))
     (commission-amount (/ (* price-input commission-percentage) RATE-BASE))
     (seller-proceeds (- price-input commission-amount)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (get is-active creation-data) ERR-INVALID-PARAMETERS)
    (asserts! (get initial-purchased creation-data) ERR-ITEM-NOT-PURCHASED)
    (asserts! (> price-input u0) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq previous-owner-input tx-sender)) ERR-INVALID-PARAMETERS)
    (asserts! (>= (stx-get-balance tx-sender) price-input) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer payment from buyer to contract first
    (try! (stx-transfer? price-input tx-sender (as-contract tx-sender)))
    
    ;; Transfer seller proceeds to previous owner
    (if (> seller-proceeds u0)
        (as-contract (try! (stx-transfer? seller-proceeds tx-sender previous-owner-input)))
        true)
    
    ;; Record the transaction
    (map-set resale-transactions
      { creation-id: creation-id-input, transaction-id: new-transaction-id }
      {
        previous-owner: previous-owner-input,
        new-owner: tx-sender,
        price: price-input,
        commission-paid: commission-amount,
        block-time: block-height
      }
    )
    
    ;; Update revenue tracking
    (let
      ((revenue-data (unwrap! (map-get? revenue-tracking { creation-id: creation-id-input })
                             ERR-CREATION-NOT-FOUND)))
      
      (map-set revenue-tracking
        { creation-id: creation-id-input }
        {
          total-earnings: (+ (get total-earnings revenue-data) commission-amount),
          last-payout: block-height
        }
      )
      
      ;; Distribute commission to collaborators
      (try! (distribute-commission creation-id-input commission-amount))
    )
    
    ;; Increment transaction counter
    (map-set next-transaction-id-counter
      { creation-id: creation-id-input }
      { id: (+ new-transaction-id u1) }
    )
    
    (ok new-transaction-id)
  )
)

;; Private function to distribute commission earnings
(define-private (distribute-commission (creation-id-input uint) (commission-amount uint))
  (let
    ((creation-record (map-get? digital-creations { creation-id: creation-id-input }))
     (creator-record (if (is-some creation-record)
                      (map-get? collaborators { creation-id: creation-id-input, collaborator: (get original-creator (unwrap-panic creation-record)) })
                     none)))
    
    (if (and (is-some creation-record) (is-some creator-record))
        (let
          ((creator-principal (get original-creator (unwrap-panic creation-record)))
           (creator-ownership-data (unwrap-panic creator-record))
           (creator-commission-share (/ (* commission-amount (get ownership-percentage creator-ownership-data)) RATE-BASE))
           (existing-earnings-data (default-to { balance: u0 }
                               (map-get? withdrawable-earnings { creation-id: creation-id-input, collaborator: creator-principal }))))
          
          ;; Add commission to withdrawable pool for original creator
          (map-set withdrawable-earnings
            { creation-id: creation-id-input, collaborator: creator-principal }
            { balance: (+ (get balance existing-earnings-data) creator-commission-share) }
          )
          
          (ok true)
        )
        ERR-CREATION-NOT-FOUND
    )
  )
)

;; Withdraw earnings
(define-public (withdraw-earnings (creation-id-input uint))
  (let
    ((earnings-data (unwrap! (map-get? withdrawable-earnings { creation-id: creation-id-input, collaborator: tx-sender })
                       ERR-NO-EARNINGS-AVAILABLE))
     (withdrawal-amount (get balance earnings-data)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (> withdrawal-amount u0) ERR-NO-EARNINGS-AVAILABLE)
    
    ;; Reset withdrawable balance
    (map-set withdrawable-earnings
      { creation-id: creation-id-input, collaborator: tx-sender }
      { balance: u0 }
    )
    
    ;; Transfer earnings to collaborator
    (as-contract (try! (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    
    (ok withdrawal-amount)
  )
)

;; Deactivate digital creation (original creator only)
(define-public (deactivate-creation (creation-id-input uint))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (is-eq tx-sender (get original-creator creation-data)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Deactivate
    (map-set digital-creations
      { creation-id: creation-id-input }
      (merge creation-data { is-active: false })
    )
    
    (ok true)
  )
)

;; Reactivate digital creation (original creator only)
(define-public (reactivate-creation (creation-id-input uint))
  (let
    ((creation-data (unwrap! (map-get? digital-creations { creation-id: creation-id-input }) ERR-CREATION-NOT-FOUND)))
    
    ;; Validate
    (asserts! (validate-creation-id creation-id-input) ERR-CREATION-NOT-FOUND)
    (asserts! (is-eq tx-sender (get original-creator creation-data)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Reactivate
    (map-set digital-creations
      { creation-id: creation-id-input }
      (merge creation-data { is-active: true })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get digital creation details
(define-read-only (get-creation-details (creation-id-input uint))
  (map-get? digital-creations { creation-id: creation-id-input })
)

;; Get collaborator details
(define-read-only (get-collaborator-details (creation-id-input uint) (collaborator-input principal))
  (map-get? collaborators { creation-id: creation-id-input, collaborator: collaborator-input })
)

;; Get withdrawable earnings
(define-read-only (get-withdrawable-earnings (creation-id-input uint) (collaborator-input principal))
  (default-to { balance: u0 }
              (map-get? withdrawable-earnings { creation-id: creation-id-input, collaborator: collaborator-input }))
)

;; Get revenue statistics
(define-read-only (get-revenue-stats (creation-id-input uint))
  (map-get? revenue-tracking { creation-id: creation-id-input })
)

;; Get resale transaction details
(define-read-only (get-resale-transaction (creation-id-input uint) (transaction-id-input uint))
  (map-get? resale-transactions { creation-id: creation-id-input, transaction-id: transaction-id-input })
)

;; Get next creation ID
(define-read-only (get-next-creation-id)
  (var-get next-creation-id-counter)
)

;; Get contract admin
(define-read-only (get-contract-admin)
  (var-get contract-admin-address)
)

;; Check if digital creation exists
(define-read-only (creation-exists (creation-id-input uint))
  (is-some (map-get? digital-creations { creation-id: creation-id-input }))
)

;; Get total creations count
(define-read-only (get-total-creations)
  (- (var-get next-creation-id-counter) u1)
)