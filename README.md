# Digital Creation Revenue Sharing Smart Contract

A Clarity smart contract that enables automatic revenue distribution for digital creations, supporting collaborative works, initial sales, and ongoing resale commissions.

## Overview

This smart contract provides a comprehensive system for managing digital creations and their revenue streams. It allows creators to register their works, add collaborators with defined ownership percentages, and automatically distribute earnings from both initial sales and subsequent resales.

## Key Features

### 🎨 Creation Management
- **Register Digital Creations**: Store metadata including name, description, pricing, and commission rates
- **Multi-Creator Support**: Add collaborators with specific ownership percentages and roles
- **Flexible Ownership**: Original creators can modify collaborator shares before initial sale
- **Token Integration**: Link external NFT/token contracts to creations

### 💰 Revenue Distribution
- **Initial Sale Processing**: Automatic distribution of initial purchase proceeds to all collaborators
- **Resale Commissions**: Configurable commission rates (up to 30%) on all secondary sales
- **Proportional Distribution**: Revenue shared based on ownership percentages
- **Withdrawal System**: Collaborators can claim their earnings individually

### 🔒 Access Control
- **Creator Authorization**: Only original creators can modify creation settings and collaborators
- **Secure Transactions**: Built-in validation and balance checks
- **Active/Inactive Status**: Creators can temporarily disable their creations

## Core Functions

### Creation Management
```clarity
;; Register a new digital creation
(register-creation name summary initial-cost commission-rate)

;; Add a collaborator with ownership percentage
(add-collaborator creation-id collaborator-address ownership-percentage position)

;; Remove a collaborator (returns ownership to creator)
(remove-collaborator creation-id collaborator-address)

;; Link external token contract
(link-token-contract creation-id token-contract-address)
```

### Sales & Revenue
```clarity
;; Process initial purchase
(initial-purchase creation-id)

;; Record a resale transaction
(record-resale-transaction creation-id previous-owner price)

;; Withdraw accumulated earnings
(withdraw-earnings creation-id)
```

### Read-Only Functions
```clarity
;; Get creation details
(get-creation-details creation-id)

;; Get collaborator information
(get-collaborator-details creation-id collaborator-address)

;; Check withdrawable earnings
(get-withdrawable-earnings creation-id collaborator-address)

;; Get revenue statistics
(get-revenue-stats creation-id)
```

## Data Structure

### Digital Creations
- **ID**: Unique identifier
- **Metadata**: Name, summary, creator
- **Pricing**: Initial cost and commission rate
- **Status**: Active/inactive, purchase status
- **Integration**: Optional token contract link

### Collaborators
- **Ownership**: Percentage-based ownership (out of 1000)
- **Role**: Description of collaborator's contribution
- **Earnings**: Accumulated withdrawable balance

### Transactions
- **Sales History**: Complete record of all resales
- **Commission Tracking**: Automatic calculation and distribution
- **Revenue Analytics**: Total earnings and distribution statistics

## Usage Examples

### 1. Register a Digital Creation
```clarity
;; Register artwork with 5% resale commission
(contract-call? .revenue-sharing register-creation
  u"Digital Masterpiece"
  u"A stunning digital artwork"
  u1000000  ;; 1 STX initial price
  u50)      ;; 5% commission rate
```

### 2. Add Collaborators
```clarity
;; Add collaborator with 30% ownership
(contract-call? .revenue-sharing add-collaborator
  u1                    ;; creation ID
  'SP2X7...'           ;; collaborator address  
  u300                 ;; 30% ownership
  "co-artist")         ;; role description
```

### 3. Process Sales
```clarity
;; Initial purchase
(contract-call? .revenue-sharing initial-purchase u1)

;; Record resale
(contract-call? .revenue-sharing record-resale-transaction
  u1                    ;; creation ID
  'SP1Y8...'           ;; previous owner
  u1500000)            ;; sale price (1.5 STX)
```

## Commission & Revenue Flow

1. **Initial Sale**: 100% of proceeds distributed to collaborators based on ownership percentages
2. **Resale Commissions**: Configurable percentage (0-30%) taken from each resale
3. **Revenue Distribution**: Commissions automatically allocated to collaborators' withdrawable balances
4. **Withdrawal**: Collaborators can claim their accumulated earnings at any time

## Security Features

- **Input Validation**: Comprehensive checks for all parameters
- **Balance Verification**: Ensures sufficient funds before transactions
- **Authorization Controls**: Creator-only functions for sensitive operations
- **Overflow Protection**: Safe arithmetic operations throughout

## Error Handling

The contract includes detailed error codes for different scenarios:
- `ERR-UNAUTHORIZED-ACCESS`: Non-creator attempting restricted operations
- `ERR-CREATION-NOT-FOUND`: Invalid creation ID
- `ERR-INSUFFICIENT-BALANCE`: Insufficient STX for transaction
- `ERR-INVALID-RATE`: Commission rate exceeds maximum (30%)
- `ERR-NO-EARNINGS-AVAILABLE`: No withdrawable earnings

## Deployment Notes

- **Network**: Compatible with Stacks blockchain
- **Dependencies**: No external dependencies required
- **Gas Optimization**: Efficient data structures and minimal storage operations
- **Upgradeability**: Contract is immutable once deployed
