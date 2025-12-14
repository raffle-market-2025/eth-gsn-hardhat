import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  FundsReceived,
  RaffleEnter,
  WinnerPicked
} from "../generated/PromoRaffle/PromoRaffle"

export function createFundsReceivedEvent(
  from: Address,
  amount: BigInt
): FundsReceived {
  let fundsReceivedEvent = changetype<FundsReceived>(newMockEvent())

  fundsReceivedEvent.parameters = new Array()

  fundsReceivedEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  fundsReceivedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return fundsReceivedEvent
}

export function createRaffleEnterEvent(
  player: Address,
  country3: Bytes,
  _lastTimestamp: BigInt
): RaffleEnter {
  let raffleEnterEvent = changetype<RaffleEnter>(newMockEvent())

  raffleEnterEvent.parameters = new Array()

  raffleEnterEvent.parameters.push(
    new ethereum.EventParam("player", ethereum.Value.fromAddress(player))
  )
  raffleEnterEvent.parameters.push(
    new ethereum.EventParam("country3", ethereum.Value.fromFixedBytes(country3))
  )
  raffleEnterEvent.parameters.push(
    new ethereum.EventParam(
      "_lastTimestamp",
      ethereum.Value.fromUnsignedBigInt(_lastTimestamp)
    )
  )

  return raffleEnterEvent
}

export function createWinnerPickedEvent(
  cycle: BigInt,
  players: Array<Address>,
  winner: Address
): WinnerPicked {
  let winnerPickedEvent = changetype<WinnerPicked>(newMockEvent())

  winnerPickedEvent.parameters = new Array()

  winnerPickedEvent.parameters.push(
    new ethereum.EventParam("cycle", ethereum.Value.fromUnsignedBigInt(cycle))
  )
  winnerPickedEvent.parameters.push(
    new ethereum.EventParam("players", ethereum.Value.fromAddressArray(players))
  )
  winnerPickedEvent.parameters.push(
    new ethereum.EventParam("winner", ethereum.Value.fromAddress(winner))
  )

  return winnerPickedEvent
}
