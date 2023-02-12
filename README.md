# [Interest Protocol](https://sui.interestprotocol.com/)

 <p> <img width="50px"height="50px" src="./assets/logo.png" /></p> 
 
 Stable & Volatile DEX on the [Sui](https://sui.io/) Network.  
  
## Quick start  
  
Make sure you have the latest version of the Sui binaries installed on your machine

[Instructions here](https://docs.sui.io/devnet/build/install)

### Run tests

```bash
  sui move test
```

### Publish

```bash
  sui client publish --gas-budget 50000
```

## Functionality

The Interest Protocol DEX allows users to create pools, add/remove liquidity and trade.

The DEX supports two types of pools denoted as:

- **Volatile:** `k = x * y` popularized by [Uniswap](https://uniswap.org/whitepaper.pdf)
- **Stable:** `k = yx^3 + xy^3` inspired by Curve's algorithm.

> The DEX will route the trade to the most profitable pool (volatile vs
> stable).

### Current Features

- Add/Remove Liquidity
- Swap: Pool<BTC, Ether> | Ether -> BTC | BTC -> Ether
- Create Pool: Users can only create volatile pools
- One Hop Swap: Pool<BTC, Ether> & Pool<Ether, USDC> | BTC -> Ether -> USDC | USDC -> Ether -> BTC
- Two Hop Swap: Pool<BTC, Ether> & Pool<Ether, USDC> & Pool<Sui, USDC> | BTC -> Ether -> USDC -> Sui | Sui -> USDC -> Ether -> BTC
- Farms to deposit VLPCoins and SLPCoins to farm IPX tokens
- Flash loans

### Future Features

- TWAP Oracle
- [Concentrated Liquidity](https://uniswap.org/whitepaper-v3.pdf)

## Live

Go to [here (Sui Interest Protocol)](https://sui.interestprotocol.com/) and see what we have prepared for you

## Contact Us

- Twitter: [@interest_dinero](https://twitter.com/interest_dinero)
- Discord: https://discord.gg/interestprotocol
- Telegram: https://t.me/interestprotocol
- Email: [contact@interestprotocol.com](mailto:contact@interestprotocol.com)
- Medium: [@interestprotocol](https://medium.com/@interestprotocol)
