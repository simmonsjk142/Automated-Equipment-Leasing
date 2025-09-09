# 🚜 EquipLease - Automated Equipment Leasing

[![Clarity](https://img.shields.io/badge/Clarity-Smart%20Contract-blue)](https://clarity-lang.org/)
[![Stacks](https://img.shields.io/badge/Stacks-Blockchain-purple)](https://www.stacks.co/)

A **trustless** smart contract system for automated agricultural equipment leasing built on the Stacks blockchain. 🌾

## 🎯 Overview

EquipLease enables farmers and equipment owners to engage in secure, automated leasing agreements without intermediaries. The contract handles deposits, payments, dispute resolution, and equipment ratings seamlessly.

## ✨ Features

- 📋 **Equipment Registration** - List equipment with daily rates and deposit requirements
- 🤝 **Automated Leasing** - Create trustless lease agreements with automatic payments
- 💰 **Deposit Management** - Secure deposit handling with condition-based returns
- ⭐ **Rating System** - Rate equipment condition and build reputation
- 🛡️ **Dispute Resolution** - Fair resolution based on equipment condition ratings
- 📊 **Analytics** - Track equipment usage and platform statistics

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Stacks CLI](https://docs.stacks.co/docs/write-smart-contracts/cli-wallet-quickstart) configured

### Installation

```bash
git clone <repository-url>
cd Automated-Equipment-Leasing
clarinet check
```

## 📖 Usage

### 1. Register Equipment 🏗️

Equipment owners can list their agricultural equipment:

```clarity
(contract-call? .EquipLease register-equipment 
  "John Deere 5075E Tractor" 
  "75HP utility tractor with loader, excellent condition"
  u50  ;; 50 STX per day
  u200 ;; 200 STX deposit
)
```

### 2. Create Lease 📝

Farmers can lease equipment by specifying duration:

```clarity
(contract-call? .EquipLease create-lease 
  u1    ;; equipment-id
  u1440 ;; 10 days (144 blocks per day)
)
```

### 3. Complete Lease ✅

When returning equipment, lessees provide condition rating:

```clarity
(contract-call? .EquipLease complete-lease 
  u1 ;; lease-id
  u5 ;; excellent condition (1-5 scale)
)
```

### 4. Manage Equipment 🔧

Equipment owners can update availability and rates:

```clarity
;; Update availability
(contract-call? .EquipLease update-equipment-availability u1 false)

;; Update rates
(contract-call? .EquipLease update-equipment-rates u1 u60 u250)
```

## 🔍 Query Functions

### Get Equipment Details
```clarity
(contract-call? .EquipLease get-equipment u1)
```

### Check Lease Information
```clarity
(contract-call? .EquipLease get-lease u1)
```

### Calculate Lease Cost
```clarity
(contract-call? .EquipLease calculate-lease-cost u1 u1440)
```

### View Equipment Rating
```clarity
(contract-call? .EquipLease get-equipment-rating u1)
```

### Platform Statistics
```clarity
(contract-call? .EquipLease get-platform-stats)
```

## 💡 How It Works

1. **Registration** 📋 - Equipment owners register their assets with daily rates and required deposits
2. **Leasing** 🤝 - Lessees pay total cost upfront (daily rate × days + deposit)
3. **Usage** 🚜 - Equipment is marked as unavailable during lease period
4. **Return** 🔄 - Lessor receives payment, deposit returned based on condition rating
5. **Rating** ⭐ - Equipment builds reputation through condition ratings

## 💰 Fee Structure

- **Platform Fee**: 5% of total lease cost
- **Deposit Return**: 
  - Full return for ratings 4-5 ⭐⭐⭐⭐⭐
  - 50% return for ratings 1-3 ⭐⭐⭐

## 🛡️ Security Features

- **Trustless Operation** - No intermediaries required
- **Automated Payments** - Smart contract handles all transactions
- **Deposit Protection** - Secure escrow for equipment protection
- **Owner Verification** - Only equipment owners can modify listings
- **Balance Checks** - Prevents insufficient fund transactions

## 🧪 Testing

Run the test suite:

```bash
clarinet test
```

## 📊 Contract Statistics

The contract tracks:
- Total equipment registered
- Total leases completed
- Platform revenue
- Equipment ratings and usage

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For support and questions:
- Open an issue on GitHub
- Check the [Clarity documentation](https://clarity-lang.org/)
- Visit [Stacks documentation](https://docs.stacks.co/)

---

Made with ❤️ for the agricultural community 🌾
