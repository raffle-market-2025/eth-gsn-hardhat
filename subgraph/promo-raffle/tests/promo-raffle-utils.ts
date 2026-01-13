import { newMockEvent } from "matchstick-as"
import { ethereum, Address, Bytes, BigInt } from "@graphprotocol/graph-ts"
import {
  RaffleEnter,
  RaffleFundsReceived,
  RafflePrizePaid,
  WinnerPicked
} from "../generated/PromoRaffle/PromoRaffle"

export function createRaffleEnterEvent(
  _player: Address,
  _ipHash: Bytes,
  _country2: Bytes,
  _lastTimestamp: BigInt,
  cycle: BigInt
): RaffleEnter {
  let raffleEnterEvent = changetype<RaffleEnter>(newMockEvent())

  raffleEnterEvent.parameters = new Array()

  raffleEnterEvent.parameters.push(
    new ethereum.EventParam("_player", ethereum.Value.fromAddress(_player))
  )
  raffleEnterEvent.parameters.push(
    new ethereum.EventParam("_ipHash", ethereum.Value.fromFixedBytes(_ipHash))
  )
  raffleEnterEvent.parameters.push(
    new ethereum.EventParam(
      "_country2",
      ethereum.Value.fromFixedBytes(_country2)
    )
  )
  raffleEnterEvent.parameters.push(
    new ethereum.EventParam(
      "_lastTimestamp",
      ethereum.Value.fromUnsignedBigInt(_lastTimestamp)
    )
  )
  raffleEnterEvent.parameters.push(
    new ethereum.EventParam("cycle", ethereum.Value.fromUnsignedBigInt(cycle))
  )

  return raffleEnterEvent
}

export function createRaffleFundsReceivedEvent(
  from: Address,
  amount: BigInt
): RaffleFundsReceived {
  let raffleFundsReceivedEvent = changetype<RaffleFundsReceived>(newMockEvent())

  raffleFundsReceivedEvent.parameters = new Array()

  raffleFundsReceivedEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  raffleFundsReceivedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return raffleFundsReceivedEvent
}

export function createRafflePrizePaidEvent(
  winner: Address,
  amount: BigInt
): RafflePrizePaid {
  let rafflePrizePaidEvent = changetype<RafflePrizePaid>(newMockEvent())

  rafflePrizePaidEvent.parameters = new Array()

  rafflePrizePaidEvent.parameters.push(
    new ethereum.EventParam("winner", ethereum.Value.fromAddress(winner))
  )
  rafflePrizePaidEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return rafflePrizePaidEvent
}

export function createWinnerPickedEvent(
  cycle: BigInt,
  playersBeforePick: BigInt,
  winner: Address
): WinnerPicked {
  let winnerPickedEvent = changetype<WinnerPicked>(newMockEvent())

  winnerPickedEvent.parameters = new Array()

  winnerPickedEvent.parameters.push(
    new ethereum.EventParam("cycle", ethereum.Value.fromUnsignedBigInt(cycle))
  )
  winnerPickedEvent.parameters.push(
    new ethereum.EventParam(
      "playersBeforePick",
      ethereum.Value.fromUnsignedBigInt(playersBeforePick)
    )
  )
  winnerPickedEvent.parameters.push(
    new ethereum.EventParam("winner", ethereum.Value.fromAddress(winner))
  )

  return winnerPickedEvent
}
