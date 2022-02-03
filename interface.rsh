'reach 0.1';
'use strict'
// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Auction
// Author: Nicholas Shellabarger
// Version: 0.0.1 - initial
// Requires Reach v0.1.7 (stable)
// -----------------------------------------------
// FUNCS
export const max = ((a, b) => a > b ? a : b)
export const min = (a, b) => a < b ? a : b
export const feeAmount = 300000
export const transferFees = (addr, addr3, addr4) => {
  transfer(100000).to(addr) // 0.1 algo
  transfer(100000).to(addr3) // 0.1 algo
  transfer(100000).to(addr4) // 0.1 algo
}
export const minBidFunc = (currentPrice, [bidIncrementAbs, bidIncrementRel]) =>
  max(currentPrice + bidIncrementAbs,
    currentPrice + (currentPrice / 100) * bidIncrementRel)
// INTERACTS
export const common = {
  ...hasConsoleLogger,
  close: Fun([], Null)
}
export const hasSignal = {
  signal: Fun([], Null)
}
export const relayInteract = {
  ...common
}
export const depositerInteract = ({
  ...common,
  ...hasSignal
})
// PARTICIPANTS
export const Participants = () => [
  Participant('Depositer', depositerInteract),
  Participant('Relay', relayInteract),
  Participant('Auctioneer', {
    ...common,
    ...hasSignal,
    getParams: Fun([], Object({
      royaltyAddr: Address, // Royalty Address
      royaltyCents: UInt, // Royalty Cents
      token: Token, // NFT token 
      startPrice: UInt, // Start Price
      reservePrice: UInt, // Reserve Price
      bidIncrementAbs: UInt, // Bid Increment Absolute
      bidIncrementRel: UInt, // Bid Increment Relative
      deadline: UInt, // Start deadline
      maxDeadline: UInt, // Max deadline
      deadlineStep: UInt, // Deadline increment value
      unitAmount: UInt, // 1.00 ALGO
      deadlineSecs: UInt, // Start deadline (Secs) // AVM1.0 TEALv5 RELEASE 
    }))
  })
]
export const Views = () => [
  View('Auction', {
    bids: UInt, // Number of Bids Accepted *DO NOT REMOVE USED BY AUCTION CATCHUP*
    closes: UInt, // Number of Closes *DO NOT REMOVE USED BY AUCTION CATCHUP*
    token: Token, // Non-network up for auction *DO NOT REMOVE USED BY AUCTION CATCHUP*
    highestBidder: Address, // Highest Bidder Address (Default: Auctioneer Address)
    currentPrice: UInt, // Current price
    startPrice: UInt, // Start price
    reservePrice: UInt, // Reserve price
    lastCTime: UInt, // Last Pay/Publish CTime 
    endCTime: UInt, // Auction End CTime
    endSecs: UInt, // AVM1.0 TEALv5 RELEASE 
    owner: Address, // Auctioneer address
    royalties: UInt, // Royalty Cents
    closed: Bool, //
    minBid: UInt, //
  })
]
export const Api = () => [
  API('Bid', {
    getBid: Fun([UInt], Null),
    getPurchase: Fun([UInt], Null),
    close: Fun([Null], Null),
    touch: Fun([Null], Null),
  })
]
//export const main = (Depositer, Relay, Auctioneer, Auction, Bid, addrs) => {
export const App = (map) => {
  const [
    { addr, addr2, addr3, addr4 },
    { tok },
    [Depositer, Relay, Auctioneer],
    [Auction],
    [Bid]
  ] = map;
  // ---------------------------------------------
  // Auctioneer publishes prarams and deposits token
  // ---------------------------------------------
  Auctioneer.only(() => {
    const {
      royaltyAddr,
      royaltyCents,
      token,
      reservePrice,
      startPrice,
      bidIncrementAbs,
      bidIncrementRel,
      deadline,
      maxDeadline,
      unitAmount,
      deadlineStep,
      // REALTIME MECHANICS
      deadlineSecs, // AVM1.0 TEALv5 RELEASE 
    } = declassify(interact.getParams());
    assume(royaltyCents >= 0 && royaltyCents <= 99)
    assume(startPrice >= 0)
    assume(startPrice < reservePrice)
    assume(token != tok)
  })
  Auctioneer
    .publish(
      royaltyAddr,
      royaltyCents,
      reservePrice,
      startPrice,
      bidIncrementAbs,
      bidIncrementRel,
      deadline,
      maxDeadline,
      token,
      unitAmount,
      deadlineStep,
      // REALTIME MECHANICS
      deadlineSecs // AVM1.0 TEALv5 RELEASE 
    )
    .pay([300000]) // 0.3 algo
  require(royaltyCents >= 0 && royaltyCents <= 99)
  require(startPrice >= 0)
  require(startPrice < reservePrice)
  require(token != tok)

  Relay.set(addr4)

  transfer(100000).to(addr) // 0.1 algo
  transfer(100000).to(addr3) // 0.1 algo
  transfer(100000).to(addr4) // 0.1 algo

  Depositer.set(Auctioneer)
  commit()

  Depositer
    .pay([[1, token]])
    .when(true)
  Depositer.only(() => interact.signal());


  each([Auctioneer], () => interact.log("Start Auction"));

  // SET VIEW INIT
  Auction.owner.set(Auctioneer) // Set View Owner
  Auction.token.set(token) // Set View Token *DO NOT REMOVE USED BY AUCTION VIEW*
  Auction.startPrice.set(startPrice) // Set View Start Price
  Auction.reservePrice.set(reservePrice) // Set View Reserve Price
  Auction.royalties.set(royaltyCents) // Set View Royalties
  Auction.closed.set(false) // Set View Closed
  Auction.minBid.set(startPrice) //

  // ---------------------------------------------

  // ---------------------------------------------
  /*
   * USING NETWORK SECS // AVM1.0 TEALv5 RELEASE 
   */
  // ---------------------------------------------
  const nextDlSecs = dl => dl + 60
  // ---------------------------------------------

  const [
    keepGoing,
    highestBidder,
    currentPrice,
    dlSecs, // AVM1.0 TEALv5 RELEASE 
  ] =
    parallelReduce([
      /*keepGoing*/ true,
      /*highestBidder*/ Auctioneer,
      /*currentPrice*/ 0,
      /*dlSecs*/ deadlineSecs, // AVM1.0 TEALv5 RELEASE
    ])
      .define(() => {
        // SET VIEW ITER
        Auction.highestBidder.set(highestBidder) // Set View Highest Bidder
        Auction.currentPrice.set(currentPrice) // Set View Current Price
        Auction.endSecs.set(dlSecs) // Set View Deadline (Secs)
        Auction.minBid.set(minBidFunc(currentPrice, [bidIncrementAbs, bidIncrementRel])) // Set View Min Bid
      })
      .invariant(balance() == currentPrice)
      .while(keepGoing)
      /*
       * Touch auction
       */
      .api(Bid.touch,
        ((_) => 0),
        ((_, k) => {
          k(null)
          return [
            keepGoing,
            highestBidder,
            currentPrice,
            dlSecs,
          ]
        })
      )
      /*
       * Accept Auction Bid
       */
      // TODO: require bid to be made before deadline
      .api(Bid.getBid,
        ((msg) => assume(true
          && lastConsensusSecs() < dlSecs
          && msg >= minBidFunc(currentPrice, [bidIncrementAbs, bidIncrementRel])
          && msg >= startPrice)),
        ((msg) => msg),
        ((msg, k) => {
          require(true
            && lastConsensusSecs() < dlSecs
            && msg >= minBidFunc(currentPrice, [bidIncrementAbs, bidIncrementRel])
            && msg >= startPrice)
          transfer(currentPrice).to(highestBidder)
          k(null)
          return [
            /*keepGoing*/ true,
            /*highestBidder*/this,
            /*currentPrice*/msg,
            nextDlSecs(dlSecs),
          ]
        }))
      /*
       * Accept purchase
       * Can occur after end of auction
       * Ends auction
       */
      .api(Bid.getPurchase,
        ((msg) => assume(true
          && lastConsensusSecs() >= dlSecs
          && currentPrice < reservePrice // prevent purchase down after reservePrice is met
          && msg >= reservePrice // prevent purchase below reserve price
        )),
        ((msg) => msg),
        ((msg, k) => {
          require(true
            && lastConsensusSecs() >= dlSecs
            && currentPrice < reservePrice // prevent purchase down after reservePrice is met
            && msg >= reservePrice // prevent purchase below reserve price
          )
          transfer(currentPrice).to(highestBidder)
          k(null)
          return [
            /*keepGoing*/ false,
            /*highestBidder*/this,
            /*currentPrice*/msg,
            /*dlSecs*/dlSecs,
          ]
        }))
      /*
       * Close Auction
       */
      .api(Bid.close,
        ((_) => 0),
        ((_, k) => {
          k(null)
          return [
            /*keepGoing*/ lastConsensusSecs() < dlSecs, // only allow auctions to be closed at end of countdown
            highestBidder,
            currentPrice,
            dlSecs,
          ]
        })
      )
      .timeout(false)

  // ---------------------------------------------
  /*
   * Recv Balance/Token
   */
  // ---------------------------------------------
  // set balance / balance (token) recievers based on
  // current price and reservePrice
  const cent = balance() / 100
  const royaltyAmount = royaltyCents * cent
  const platformAmount = cent
  const recvAmount = balance() - (royaltyAmount + platformAmount)
  const isReservePriceMet = currentPrice >= reservePrice
  // requires transfer to highestBidder
  const transferButLast = () => {
    if (isReservePriceMet) {
      transfer([[balance(token), token]]).to(highestBidder) // to highestBidder
      transfer(royaltyAmount).to(royaltyAddr); // to creator
      transfer(platformAmount).to(addr2); // to platform
      transfer(recvAmount).to(Auctioneer); // to auctioneer
    } else {
      transfer(recvAmount + royaltyAmount + platformAmount).to(highestBidder); // to highestBidder 
      transfer([[balance(token), token]]).to(Auctioneer) // to auctioneer
    }
  }
  //const transferLast = () => {
  //  if(isReservePriceMet) {
  //    // pass
  //  } else {
  //    // pass
  //  }
  //}
  // ---------------------------------------------

  // ---------------------------------------------
  /*
   * Balance transfer
   */
  // ---------------------------------------------
  transferButLast()
  // ---------------------------------------------

  // SET VIEW TERM
  Auction.closed.set(true) // Set View Closed

  commit()
  Relay.publish()

  // -----------------------------------------------
  /* Intuition
   * At this point auction is over
   * All that is left is for the auctioneer to
   * release their part and delete the application*/
  // -----------------------------------------------

  // ---------------------------------------------
  /*
   * Balance transfer
   * =============================================
   * Expect reserve price to be met resulting in
   * balance payment sent to Auctioneer
   * Otherwise, bid is returned to the highest bidder
   * =============================================
   */
  // ---------------------------------------------
  //transferLast()
  // ---------------------------------------------

  // ---------------------------------------------
  /*
   * END AUCTION
   */
  // ---------------------------------------------
  /*
   * EXIT
   */
  transfer(balance(tok), tok).to(addr)
  commit();
  exit();
}
// ----------------------------------------------