import { Bytes, ethereum } from "@graphprotocol/graph-ts";

import {
  RaffleEnter as RaffleEnterEvent,
  WinnerPicked as WinnerPickedEvent,
  RaffleFundsReceived as RaffleFundsReceivedEvent,
  RafflePrizePaid as RafflePrizePaidEvent,
} from "../generated/PromoRaffle/PromoRaffle";

import {
  RaffleEnter,
  WinnerPicked,
  RaffleFundsReceived,
  RafflePrizePaid,
} from "../generated/schema";

function idOf(event: ethereum.Event): Bytes {
  // Unique per log: tx hash + log index
  return event.transaction.hash.concatI32(event.logIndex.toI32());
}

export function handleRaffleEnter(event: RaffleEnterEvent): void {
  const e = new RaffleEnter(idOf(event));

  e._player = event.params._player;
  e._ipHash = event.params._ipHash;       // bytes32 -> Bytes
  e._country3 = event.params._country3;   // bytes3  -> Bytes
  e._lastTimestamp = event.params._lastTimestamp;
  e.cycle = event.params.cycle;

  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;

  e.save();
}

export function handleWinnerPicked(event: WinnerPickedEvent): void {
  const e = new WinnerPicked(idOf(event));

  e.cycle = event.params.cycle;
  e.playersBeforePick = event.params.playersBeforePick;
  e.winner = event.params.winner;

  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;

  e.save();
}

export function handleRaffleFundsReceived(event: RaffleFundsReceivedEvent): void {
  const e = new RaffleFundsReceived(idOf(event));

  e.from = event.params.from;
  e.amount = event.params.amount;

  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;

  e.save();
}

export function handleRafflePrizePaid(event: RafflePrizePaidEvent): void {
  const e = new RafflePrizePaid(idOf(event));

  e.winner = event.params.winner;
  e.amount = event.params.amount;

  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;

  e.save();
}