import {
  RaffleEnter as RaffleEnterEvent,
  RaffleFundsReceived as RaffleFundsReceivedEvent,
  RafflePrizePaid as RafflePrizePaidEvent,
  WinnerPicked as WinnerPickedEvent
} from "../generated/PromoRaffle/PromoRaffle"
import {
  RaffleEnter,
  RaffleFundsReceived,
  RafflePrizePaid,
  WinnerPicked
} from "../generated/schema"
import { Bytes } from "@graphprotocol/graph-ts"

export function handleRaffleEnter(event: RaffleEnterEvent): void {
  let entity = new RaffleEnter(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity._player = event.params._player
  entity._ip = event.params._ip
  entity._country3 = event.params._country3
  entity._lastTimestamp = event.params._lastTimestamp

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleFundsReceived(
  event: RaffleFundsReceivedEvent
): void {
  let entity = new RaffleFundsReceived(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.from = event.params.from
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRafflePrizePaid(event: RafflePrizePaidEvent): void {
  let entity = new RafflePrizePaid(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.winner = event.params.winner
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleWinnerPicked(event: WinnerPickedEvent): void {
  let entity = new WinnerPicked(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.cycle = event.params.cycle
  entity.players = changetype<Bytes[]>(event.params.players)
  entity.winner = event.params.winner

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
