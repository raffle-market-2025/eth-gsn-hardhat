import {
  FundsReceived as FundsReceivedEvent,
  RaffleEnter as RaffleEnterEvent,
  WinnerPicked as WinnerPickedEvent
} from "../generated/PromoRaffle/PromoRaffle"
import { FundsReceived, RaffleEnter, WinnerPicked } from "../generated/schema"
import { Bytes } from "@graphprotocol/graph-ts"

export function handleFundsReceived(event: FundsReceivedEvent): void {
  let entity = new FundsReceived(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.from = event.params.from
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleEnter(event: RaffleEnterEvent): void {
  let entity = new RaffleEnter(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.player = event.params.player
  entity.country3 = event.params.country3
  entity._lastTimestamp = event.params._lastTimestamp

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
