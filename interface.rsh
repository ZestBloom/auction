"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: NFT Jam Auction
// Version: 0.1.1 - fix runtime issues
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------

import {
  State as BaseState,
  TokenState,
  RoyaltyState,
  Params as BaseParams,
  RoyaltyParams,
  max,
  view,
  baseState,
  baseEvents
} from "@KinnFoundation/base#base-v0.1.11r10:interface.rsh";

// CONSTANTS

const SERIAL_VER = 0;

const DIST_LENGTH = 9;

const ADDR_RESERVED_ADDR = 2;

// TYPES

const AuctionState = Struct([
  ["bids", UInt], // number of bids
  ["highestBidder", Address], // highest bidder
  ["currentPrice", UInt], // current price
  ["startPrice", UInt], // start price
  ["reservePrice", UInt], // reserve price
  ["minBid", UInt], // min bid
  ["endSecs", UInt], // end seconds
  ["who", Address], // who"
]);

export const State = Struct([
  ...Struct.fields(BaseState),
  ...Struct.fields(TokenState),
  ...Struct.fields(RoyaltyState(DIST_LENGTH)),
  ...Struct.fields(AuctionState),
]);

export const AuctionParams = Object({
  tokenAmount: UInt, // Amount of NFT token
  startPrice: UInt, // Start Price
  reservePrice: UInt, // Reserve Price
  bidIncrementAbs: UInt, // Bid Increment Absolute
  bidIncrementRel: UInt, // Bid Increment Relative
  deadlineSecs: UInt, // Start deadline (Secs) // AVM1.0 TEALv5 RELEASE
});

export const Params = Object({
  ...Object.fields(BaseParams),
  ...Object.fields(RoyaltyParams(DIST_LENGTH)),
  ...Object.fields(AuctionParams),
});

// FUN

const fState = (State) => Fun([], State);
const fGetBid = Fun([UInt], Null);
const fGetPurchase = Fun([Address], Null);
const fClaim = Fun([Address], Null);
const fClose = Fun([], Null);

// REMOTE FUN

export const rState = (ctc, State) => {
  const r = remote(ctc, { state: fState(State) });
  return r.state();
};

export const rGetBid = (ctc, amt) => {
  const r = remote(ctc, { getBid: fGetBid });
  return r.getBid(amt);
};

export const rGetPurchase = (ctc, addr) => {
  const r = remote(ctc, { getPurchase: fGetPurchase });
  return r.getPurchase(addr);
};

export const rClaim = (ctc, addr) => {
  const r = remote(ctc, { claim: fClaim });
  return r.claim(addr);
};

export const rClose = (ctc) => {
  const r = remote(ctc, { close: fClose });
  return r.close();
};

// API

export const api = {
  getBid: fGetBid,
  getPurchase: fGetPurchase,
  claim: fClaim,
  close: fClose,
};

// FUNCS

export const minBidFunc = (currentPrice, [bidIncrementAbs, bidIncrementRel]) =>
  max(
    currentPrice + bidIncrementAbs,
    currentPrice + (currentPrice / 100) * bidIncrementRel
  );

// INTERACTS

const managerInteract = {
  getParams: Fun([], Params),
};

const relayInteract = {};

const eveInteract = {};

// EVENTS

export const auctionEvents = {
  appBid: [UInt, Address, UInt],
  appPurchase: [UInt, Address, UInt],
};

// CONTRACT

export const Event = () => [Events({ ...baseEvents, ...auctionEvents })];

export const Participants = () => [
  Participant("Manager", managerInteract),
  Participant("Relay", relayInteract),
  Participant("Eve", eveInteract),
];

export const Views = () => [View(view(State))];

export const Api = () => [API(api)];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token },
    [addr, _],
    [Manager, Relay, _],
    [v],
    [a],
    [e],
  ] = map;
  Manager.only(() => {
    const {
      tokenAmount,
      startPrice,
      reservePrice,
      bidIncrementAbs,
      bidIncrementRel,
      deadlineSecs,
      addrs,
      distr,
      royaltyCap,
    } = declassify(interact.getParams());
  });
  Manager.publish(
    tokenAmount,
    startPrice,
    reservePrice,
    bidIncrementAbs,
    bidIncrementRel,
    deadlineSecs,
    addrs,
    distr,
    royaltyCap
  )
    .pay([amt + SERIAL_VER, [tokenAmount, token]])
    .check(() => {
      check(startPrice > 0, "Start price must be greater than 0");
      check(
        startPrice <= reservePrice,
        "Start price must be less than reserve price"
      );
      check(tokenAmount > 0, "Token amount must be greater than 0");
      check(
        distr.sum() <= royaltyCap,
        "distr sum must be less than or equal to royaltyCap"
      );
      check(
        royaltyCap == (10 * reservePrice) / 1000000,
        "royaltyCap must be 10x of reservePrice"
      );
    })
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + SERIAL_VER).to(addr);
  e.appLaunch();

  const distrTake = distr.sum();

  const initialState = {
    ...baseState(Manager),
    token,
    tokenAmount,
    bids: 0,
    highestBidder: Manager,
    currentPrice: 0,
    startPrice,
    reservePrice,
    minBid: startPrice,
    endSecs: deadlineSecs,
    who: Manager,
    addrs: Array.set(addrs, ADDR_RESERVED_ADDR, addr),
    distr,
    royaltyCap,
  };

  const nextDlSecs = (dl) => dl + 60;

  const [s] = parallelReduce([initialState])
    .define(() => {
      v.state.set(State.fromObject(s));
    })
    // TOKEN BALANCE
    .invariant(
      implies(!s.closed, balance(token) == s.tokenAmount),
      "token balance is accurate before close"
    )
    .invariant(
      implies(s.closed, balance(token) == 0),
      "token balance is accurate after close"
    )
    // BALANCE
    .invariant(
      implies(!s.closed, balance() == s.currentPrice),
      "balance is accurate before close"
    )
    .invariant(
      implies(s.closed, balance() == s.distr.slice(2, DIST_LENGTH - 2).sum()),
      "balance is accurate after close"
    )
    .while(!s.closed)
    // api: get bid
    //  allows anyone to bid
    .api_(a.getBid, (msg) => {
      check(msg >= s.minBid, "Bid must be greater than min bid");
      check(msg >= s.startPrice, "Bid must be greater than start price");
      return [
        msg,
        (k) => {
          require(thisConsensusSecs() < s.endSecs, "Auction must not be over");
          k(null);
          transfer(s.currentPrice).to(s.highestBidder);
          e.appBid(thisConsensusSecs(), this, msg);
          return [
            {
              ...s,
              bids: s.bids + 1,
              highestBidder: this,
              currentPrice: msg,
              endSecs: nextDlSecs(s.endSecs),
              minBid: minBidFunc(msg, [bidIncrementAbs, bidIncrementRel]),
            },
          ];
        },
      ];
    })
    // api: get purchase
    //  allows anyone to purchase
    .api_(a.getPurchase, (cAddr) => {
      check(s.currentPrice < s.reservePrice, "Reserve price must be unmet");
      return [
        s.reservePrice,
        (k) => {
          require(thisConsensusSecs() >= s.endSecs, "Auction must be over");
          const partTake = s.reservePrice / royaltyCap;
          const proceedTake = partTake * distrTake;
          const sellerTake = s.reservePrice - proceedTake;
          transfer(s.currentPrice).to(s.highestBidder);
          transfer(sellerTake).to(Manager);
          transfer([[s.tokenAmount, token]]).to(this);
          transfer(distr[0] * partTake).to(cAddr);
          transfer(distr[1] * partTake).to(addrs[1]);
          e.appPurchase(thisConsensusSecs(), this, s.reservePrice);
          k(null);
          return [
            {
              ...s,
              closed: true,
              highestBidder: this,
              currentPrice: s.reservePrice,
              addrs: Array.set(s.addrs, 0, cAddr),
              distr: Array.set(Array.set(distr.map((d) => d * partTake), 0, 0), 1, 0),
              who: this,
            },
          ];
        },
      ];
    })
    // api: claim
    //  allows proceeds to be claimed
    .api_(a.claim, (cAddr) => {
      check(s.currentPrice >= s.reservePrice, "Reserve price must be met");
      return [
        (k) => {
          require(thisConsensusSecs() >= s.endSecs, "Auction must be over");
          const partTake = s.currentPrice / royaltyCap;
          const proceedTake = partTake * distrTake;
          const sellerTake = s.currentPrice - proceedTake;
          transfer(sellerTake).to(Manager);
          transfer([[s.tokenAmount, token]]).to(s.highestBidder);
          transfer(distr[0] * partTake).to(cAddr);
          transfer(distr[1] * partTake).to(addrs[1]);
          k(null);
          return [
            {
              ...s,
              closed: true,
              addrs: Array.set(s.addrs, 0, cAddr),
              distr: Array.set(Array.set(distr.map((d) => d * partTake), 0, 0), 1, 0),
              who: s.highestBidder,
            },
          ];
        },
      ];
    })
    // api: close
    //  allows auction to be closed
    .api_(a.close, () => {
      check(this === Manager || this === s.highestBidder, "Must be authorized");
      check(s.currentPrice < s.reservePrice, "Reserve price must be unmet");
      return [
        (k) => {
          require(thisConsensusSecs() >= s.endSecs, "Auction must be over");
          transfer(s.currentPrice).to(s.highestBidder);
          transfer([[s.tokenAmount, token]]).to(Manager);
          k(null);
          return [
            {
              ...s,
              closed: true,
              distr: Array.replicate(DIST_LENGTH, 0),
            },
          ];
        },
      ];
    })
    .timeout(false);
  e.appClose();
  commit();
  // Step
  Relay.publish();
  transfer(s.distr[2]).to(addrs[2]); // addr
  transfer(s.distr[3]).to(addrs[3]);
  transfer(s.distr[4]).to(addrs[4]);
  transfer(s.distr[5]).to(addrs[5]);
  commit();
  // Step
  Anybody.publish();
  transfer(s.distr[6]).to(addrs[6]);
  transfer(s.distr[7]).to(addrs[7]);
  transfer(s.distr[8]).to(addrs[8]);
  commit();
  Anybody.publish();
  commit();
  exit();
};
// ----------------------------------------------
