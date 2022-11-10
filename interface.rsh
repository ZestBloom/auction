"reach 0.1";
"use strict";
// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Auction
// Author: Nicholas Shellabarger
// Version: 0.0.2 - allow sale params
// Requires Reach v0.1.7 (stable)
// -----------------------------------------------
// FUNCS
const SERIAL_VER = 0;
export const max = (a, b) => (a > b ? a : b);
export const min = (a, b) => (a < b ? a : b);
export const minBidFunc = (currentPrice, [bidIncrementAbs, bidIncrementRel]) =>
  max(
    currentPrice + bidIncrementAbs,
    currentPrice + (currentPrice / 100) * bidIncrementRel
  );
// INTERACTS
export const common = {
  ...hasConsoleLogger,
  close: Fun([], Null),
};
export const hasSignal = {
  signal: Fun([], Null),
};
export const relayInteract = {
  ...common,
};
export const depositerInteract = {
  ...common,
  ...hasSignal,
};
// PARTICIPANTS
export const Event = () => [];
export const Participants = () => [
  Participant("Auctioneer", {
    ...common,
    ...hasSignal,
    getParams: Fun(
      [],
      Object({
        royaltyAddr: Address, // Royalty Address
        royaltyCents: UInt, // Royalty Cents
        //token: Token, // NFT token
        tokenAmt: UInt, // Amount of NFT token
        startPrice: UInt, // Start Price
        reservePrice: UInt, // Reserve Price
        bidIncrementAbs: UInt, // Bid Increment Absolute
        bidIncrementRel: UInt, // Bid Increment Relative
        deadlineSecs: UInt, // Start deadline (Secs) // AVM1.0 TEALv5 RELEASE
      })
    ),
  }),
  ParticipantClass("Relay", relayInteract),
];
export const Views = () => [
  View({
    manager: Address, // Standard view: Auctioneer address
    bids: UInt, // Number of Bids Accepted *DO NOT REMOVE USED BY AUCTION CATCHUP*
    token: Token, // Non-network up for auction *DO NOT REMOVE USED BY AUCTION CATCHUP*
    tokenAmt: UInt, // Non-network up for auction *DO NOT REMOVE USED BY AUCTION CATCHUP*
    highestBidder: Address, // Highest Bidder Address (Default: Auctioneer Address)
    currentPrice: UInt, // Current price
    startPrice: UInt, // Start price
    reservePrice: UInt, // Reserve price
    lastCTime: UInt, // Last Pay/Publish CTime
    endCTime: UInt, // Auction End CTime
    endSecs: UInt, // AVM1.0 TEALv5 RELEASE
    royalties: UInt, // Royalty Cents
    closed: Bool, //
    minBid: UInt, //
    paymentToken: Token, //
  }),
];

export const Api = () => [
  API({
    getBid: Fun([UInt], Null),
    getPurchase: Fun([UInt], Null),
    close: Fun([], Null),
    touch: Fun([], Null),
  }),
];
export const App = (map) => {
  const [
    { amt, ttl, tok0: token, tok1: paymentToken },
    [addr, _],
    [Auctioneer, Relay],
    [v],
    [a],
    _,
  ] = map;
  // ---------------------------------------------
  // Auctioneer publishes prarams and deposits token
  // ---------------------------------------------
  Auctioneer.only(() => {
    const {
      // PRICE
      reservePrice,
      startPrice,
      // PRICE FUNC
      bidIncrementAbs,
      bidIncrementRel,
      // ROYALTIES
      royaltyAddr,
      royaltyCents,
      // TOKEN
      //token,
      tokenAmt,
      // REALTIME MECHANICS
      deadlineSecs,
    } = declassify(interact.getParams());
    assume(royaltyCents >= 0 && royaltyCents <= 99);
    assume(startPrice > 0);
    assume(startPrice <= reservePrice);
    assume(tokenAmt > 0);
  });
  Auctioneer.publish(
    // PRICE
    reservePrice,
    startPrice,
    // PRICE FUNC
    bidIncrementAbs,
    bidIncrementRel,
    // ROYALTIES
    royaltyAddr,
    royaltyCents,
    // TOKEN
    //token,
    tokenAmt,
    // REALTIME MECHANICS
    deadlineSecs
  )
    .pay([amt + SERIAL_VER, [tokenAmt, token]])
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  require(royaltyCents >= 0 && royaltyCents <= 99);
  require(startPrice > 0);
  require(startPrice <= reservePrice);
  require(tokenAmt > 0);

  transfer(amt + SERIAL_VER).to(addr);

  Auctioneer.only(() => interact.signal());

  // SET VIEW INIT
  v.manager.set(Auctioneer); // Set View Owner / Manager
  v.token.set(token); // Set View Token *DO NOT REMOVE USED BY AUCTION VIEW*
  v.tokenAmt.set(tokenAmt); // Set View Token *DO NOT REMOVE USED BY AUCTION VIEW*
  v.startPrice.set(startPrice); // Set View Start Price
  v.reservePrice.set(reservePrice); // Set View Reserve Price
  v.royalties.set(royaltyCents); // Set View Royalties
  v.closed.set(false); // Set View Closed
  v.minBid.set(startPrice); //
  v.paymentToken.set(paymentToken);

  // ---------------------------------------------

  // ---------------------------------------------
  /*
   * USING NETWORK SECS // AVM1.0 TEALv5 RELEASE
   */
  // ---------------------------------------------
  const nextDlSecs = (dl) => dl + 60;
  // ---------------------------------------------

  const [
    keepGoing,
    highestBidder,
    currentPrice,
    dlSecs, // AVM1.0 TEALv5 RELEASE
  ] = parallelReduce([
    /*keepGoing*/ true,
    /*highestBidder*/ Auctioneer,
    /*currentPrice*/ 0,
    /*dlSecs*/ deadlineSecs, // AVM1.0 TEALv5 RELEASE
  ])
    .define(() => {
      // SET VIEW ITER
      v.highestBidder.set(highestBidder); // Set View Highest Bidder
      v.currentPrice.set(currentPrice); // Set View Current Price
      v.endSecs.set(dlSecs); // Set View Deadline (Secs)
      v.minBid.set(
        minBidFunc(currentPrice, [bidIncrementAbs, bidIncrementRel])
      ); // Set View Min Bid
    })
    .invariant(balance(paymentToken) >= currentPrice)
    .while(keepGoing)
    /*
     * Touch auction
     */
    .api(
      a.touch,
      () => [0, [0, paymentToken]],
      (k) => {
        k(null);
        return [keepGoing, highestBidder, currentPrice, dlSecs];
      }
    )
    /*
     * Accept Auction Bid
     */
    // TODO: require bid to be made before deadline
    .api(
      a.getBid,
      (msg) => {
        assume(lastConsensusSecs() < dlSecs);
        assume(
          msg >= minBidFunc(currentPrice, [bidIncrementAbs, bidIncrementRel])
        );
        assume(msg >= startPrice);
      },
      (msg) => [0, [msg, paymentToken]],
      (msg, k) => {
        require(lastConsensusSecs() < dlSecs);
        require(msg >=
          minBidFunc(currentPrice, [bidIncrementAbs, bidIncrementRel]));
        require(msg >= startPrice);
        transfer(currentPrice, paymentToken).to(highestBidder);
        k(null);
        return [
          /*keepGoing*/ true,
          /*highestBidder*/ this,
          /*currentPrice*/ msg,
          nextDlSecs(dlSecs),
        ];
      }
    )
    /*
     * Accept purchase
     * Can occur after end of auction
     * Ends auction
     */
    .api(
      a.getPurchase,
      (msg) => {
        assume(lastConsensusSecs() >= dlSecs);
        assume(currentPrice < reservePrice); // prevent purchase down after reservePrice is met
        assume(msg >= reservePrice); // prevent purchase below reserve price
      },
      (msg) => [0, [msg, paymentToken]],
      (msg, k) => {
        require(lastConsensusSecs() >= dlSecs);
        require(currentPrice < reservePrice); // prevent purchase down after reservePrice is met
        require(msg >= reservePrice); // prevent purchase below reserve price
        transfer(currentPrice, paymentToken).to(highestBidder);
        k(null);
        return [
          /*keepGoing*/ false,
          /*highestBidder*/ this,
          /*currentPrice*/ msg,
          /*dlSecs*/ dlSecs,
        ];
      }
    )
    /*
     * Close Auction
     */
    .api(
      a.close,
      () => [0, [0, paymentToken]],
      (k) => {
        k(null);
        return [
          /*keepGoing*/ lastConsensusSecs() < dlSecs, // only allow auctions to be closed at end of countdown
          highestBidder,
          currentPrice,
          dlSecs,
        ];
      }
    )
    .timeout(false);

  // ---------------------------------------------
  /*
   * Recv Balance/Token
   */
  // ---------------------------------------------
  // set balance / balance (token) recievers based on
  // current price and reservePrice
  const cent = balance() / 100;
  const royaltyAmount = royaltyCents * cent;
  const platformAmount = cent;
  const recvAmount = balance(paymentToken) - (royaltyAmount + platformAmount);
  const isReservePriceMet = currentPrice >= reservePrice;
  // requires transfer to highestBidder
  const transferButLast = () => {
    if (isReservePriceMet) {
      transfer([[balance(token), token]]).to(highestBidder); // to highestBidder
      //transfer(royaltyAmount).to(royaltyAddr); // to creator
      transfer(recvAmount, paymentToken).to(Auctioneer); // to auctioneer
    } else {
      transfer(recvAmount + royaltyAmount + platformAmount, paymentToken).to(
        highestBidder
      );
      transfer(balance(token), token).to(Auctioneer); // to auctioneer
    }
  };
  const transferLast = () => {
    if (isReservePriceMet) {
      //transfer(platformAmount, paymentToken).to(addr); // to platform
    } else {
      // pass
    }
    transfer(balance()).to(addr); // to platform
    transfer(balance(token), token).to(addr);
    transfer(balance(paymentToken), paymentToken).to(addr);
  };
  // ---------------------------------------------

  // ---------------------------------------------
  /*
   * Balance transfer
   */
  // ---------------------------------------------
  transferButLast();
  // ---------------------------------------------

  // SET VIEW TERM
  v.closed.set(true); // Set View Closed

  commit();
  Relay.publish();

  // -----------------------------------------------
  /* Intuition
   * At this point auction is over
   * All that is left is for the auctioneer to
   * release their part and delete the application*/
  // -----------------------------------------------

  /* ---------------------------------------------
   * Balance transfer
   * =============================================
   * Expect reserve price to be met resulting in
   * balance payment sent to Auctioneer
   * Otherwise, bid is returned to the highest bidder
   * =============================================
   */
  // ---------------------------------------------
  transferLast();
  // ---------------------------------------------

  // ---------------------------------------------
  /*
   * END AUCTION
   */
  // ---------------------------------------------
  /*
   * EXIT
   */
  commit();
  exit();
};
// ----------------------------------------------
