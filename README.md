# Auction

This is a reach app in which an ASA owner of any assets can create an auction allowing bidding and price discovery on the asset during a specified time frame. After the end of the auction time the contract can be closed out and it either meets the sellers set reserve price resulting in payouts to the seller, marketplace, creator and a transfer of the asset to the highest bidder. Alternately if the reserve is not met then the contract may be closes out returning all funds and assets to their original owners or left to be sold at the reserved price.

## activation fee

0.55 ALGO

## participants

### Auctioneer

Sets auction parameters such as deadline and start price. This is the token holder.

### Depositor

This is the auctioneer after setting the token because it is not possible to publish what the token is and pay in the same step. However, it may be removed if neccesary by using the brick.

### Relay

Allowed to close auction. Reserved for platform to prevent unwanted error bombings.

## Views

### Auction

#### bids

Number of bids. May be only relevant in older version using ParticipantClass.

#### closes

Number of closes. May be only relevant in older version using ParticipantClass.

#### token

Token being auctioned

#### highestBidder

Bidder with lead initially Auctioneer

#### currentPrice

Current price of token in auction initially start price

#### startPrice

The price at the start of the auction

#### reservePrice

The price at which the auction may transfer ownership if met at the end of the auction

#### lastCTime

depreciated

#### endCTime

depreciated

#### endSecs

Time at which auction is initially schedule to end

#### owner

Auctioneer address because during the auction the token is owned by the contract

#### royalties

How much of the proceeds is goes to the asset creator. Set by the Auctioneer.

#### minBid

The lowest amount that will be accepted as the next leading bid

### api

#### getBid

Used to submit bit

#### getPurchase

Used to purchase token at end of auction

#### close

Used to close auction

#### touch

Used to touch auction

## steps

1. Auctioneer sets up auction
2. Token is deposited
3. Enter api (can bid/buy/close/touch)
4. Relay deletes app

## quickstart

commands
```bash
git clone git@github.com:ZestBloom/auction.git 
cd auction
source np.sh 
np
```

output
```json
{"info":66944916}
```

## how does it work

NP provides a nonintrusive wrapper allowing apps to be configurable before deployment and created on the fly without incurring global storage.   
Connect to the constructor and receive an app id.   
Activate the app by paying for deployment and storage cost. 
After activation, your RApp takes control.

## how to activate my app

In your the frontend of your NPR included Contractee participation. Currently, a placeholder fee is required for activation. Later an appropriate fee amount will be used.

```js
ctc = acc.contract(backend, id)
backend.Contractee(ctc, {})
```

## terms

- NP - Nash Protocol
- RAap - Reach App
- NPR - NP Reach App
- Activation - Hand off between constructor and contractee require fee to pay for deployment and storage cost incurred by constructor

## dependencies

- Reach development environment (reach compiler)
- sed - stream editor
- grep - pattern matching
- curl - request remote resource


