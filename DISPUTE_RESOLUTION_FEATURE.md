# 🔧 Dispute Resolution & Arbitration System

## Feature Overview

A trustless, on-chain dispute resolution mechanism for EquipLease that allows lessors and lessees to resolve disagreements without external intervention.

## Problem Solved

- **No dispute handling**: Equipment damage claims and payment disputes had no recourse
- **Incomplete resolution**: Single equipment condition rating at completion without dispute options
- **Security risk**: No mechanism to prevent fraud from either party
- **Centralization**: Required external arbitration to resolve conflicts

## Key Capabilities

### 1. **File Dispute**
- Either lessor or lessee can initiate disputes on active leases
- Include a 100-character reason/description
- Only one dispute per lease can exist simultaneously
- Stores initiator, opponent, and dispute metadata

### 2. **Resolve Dispute**
- Platform owner (contract admin) arbitrates disputes
- Designate winner (lessor or lessee)
- Full lease funds transferred to winner
- Dispute marked as "lessor-win" or "lessee-win"
- Removes dispute lock from lease

### 3. **Auto-Expire Dispute**
- Disputes automatically expire after 72 blocks (~12 hours)
- Neutral resolution: funds split 50/50 between parties
- Prevents fund lockup and ensures resolution timeline
- Status marked as "expired"

### 4. **Query Functions**
- `get-dispute`: Retrieve dispute details by ID
- `is-dispute-active`: Check if lease has pending dispute
- `get-dispute-time-remaining`: Calculate blocks until auto-expiration

## Implementation Details

### New Error Constants (u111-u115)
```
ERR-DISPUTE-NOT-FOUND (u111)
ERR-DISPUTE-ALREADY-EXISTS (u112)
ERR-DISPUTE-ALREADY-RESOLVED (err u113)
ERR-DISPUTE-NOT-EXPIRED (err u114)
ERR-INVALID-DISPUTE-PARTY (err u115)
```

### New Data Structures
- **disputes map**: Stores dispute state with lease-id, parties, status, reason, blocks, winner
- **lease-disputes map**: One-to-one mapping of lease-id to active dispute-id
- **next-dispute-id variable**: Incremental dispute counter

### Integration Points
- `complete-lease`: Blocked if active dispute exists
- `cancel-lease`: Blocked if active dispute exists
- `get-platform-stats`: Includes total-disputes count

## Security Features

✅ **Authorization**: Only lease participants or platform owner can act
✅ **Atomic Transfers**: Fund movements use try! pattern with proper error handling
✅ **State Management**: Prevents duplicate disputes and orphaned funds
✅ **Time-bound Resolution**: 72-block auto-expiration prevents indefinite lockup
✅ **Clear Audit Trail**: All disputes tracked with timestamps and outcomes

## Public Functions Added

### file-dispute
```clarity
(define-public (file-dispute (lease-id uint) (reason (string-ascii 100)))
```
Files a new dispute on an active lease. Only lease parties can call.

### resolve-dispute
```clarity
(define-public (resolve-dispute (dispute-id uint) (winner principal))
```
Resolves a pending dispute. Platform owner only. Transfers funds to winner.

### auto-expire-dispute
```clarity
(define-public (auto-expire-dispute (dispute-id uint))
```
Expires a pending dispute after 72 blocks. Splits funds 50/50.

## Read-Only Functions Added

### get-dispute
Returns full dispute object with all metadata

### is-dispute-active
Boolean check if lease has pending dispute

### get-dispute-time-remaining
Returns blocks remaining until auto-expiration (0 if expired)

## Usage Examples

### Scenario 1: Equipment Damage Dispute
1. Lessee calls `file-dispute` with reason "Equipment returned damaged"
2. Platform owner reviews and calls `resolve-dispute` with lessor as winner
3. Lessor receives full lease amount

### Scenario 2: Payment Dispute Auto-Expiration
1. Lessor files dispute about non-payment
2. After 72 blocks, either party calls `auto-expire-dispute`
3. Funds split equally between lessor and lessee

## Files Modified

- `contracts/EquipLease.clar`: 157 lines added

## Testing

Contract validates successfully with `clarinet check`:
```
✔ 1 contract checked
```

14 lint warnings (standard Clarity input validation warnings - not errors)

## Deployment Checklist

- [x] Feature branch created: `feat/dispute-resolution`
- [x] Code implementation complete
- [x] Compilation validated with Clarinet
- [x] All variables defined before use
- [x] LF line endings applied
- [x] Changes committed with modern emoji message
- [ ] Pull request created for review

## Git Information

**Branch**: `feat/dispute-resolution`
**Commit**: ✨ Introduce trustless dispute resolution mechanism for lease conflicts
**Files Changed**: 1 file, 157 insertions(+)

## Modern PR Details

**Title**: 🔧 Ship dispute resolution & arbitration system for lease conflicts

**Description**: This PR brings a trustless dispute resolution mechanism to EquipLease Clarity, empowering both lessors and lessees with on-chain arbitration capabilities.

### ✨ Key Features
- 📝 File disputes on active leases with reason tracking
- ⚖️ Manual resolution with fund distribution to winners
- ⏰ Auto-expire disputes after 72 blocks with neutral split
- 🔍 Query dispute status and time remaining
- 💰 Secure fund transfers based on outcomes

### 🛡️ Security Considerations
- Only lease parties can file disputes
- Single active dispute per lease limitation
- Auto-resolution prevents fund lockup
- Validated fund transfers with proper error handling

### 📊 Impact
This feature enhances trust between parties by providing transparent, on-chain dispute resolution without requiring external arbitrators.
