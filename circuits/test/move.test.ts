import { assert } from 'chai'
import { wasm } from 'circom_tester'

describe('Move', function () {
	let circuit

	before(async function () {
		circuit = await wasm('test/circom/move.t.circom')
	})

	it('Should generate the witness successfully', async function () {
		let input = {
			paths: [
				[1, 1],
				[2, 1],
				[-1, -1],
				[-1, -1],
				[-1, -1],
			],
			x1: 1, // last move
			y1: 1,
			x2: 2, // new move
			y2: 1,
		}
		const witness = await circuit.calculateWitness(input)
		await circuit.assertOut(witness, {})
	})

	it('should play the first move', async function () {
		const input = {
			paths: [
				[2, 1],
				[-1, -1],
				[-1, -1],
				[-1, -1],
				[-1, -1],
			],
			x1: -1,
			y1: -1,
			x2: 2,
			y2: 1,
		}
		try {
			await circuit.calculateWitness(input)
		} catch (err) {
			assert(false, err.message)
		}
	})

	it('should fail to play the first move', async function () {
		const input = {
			paths: [
				[-1, -1],
				[2, 1],
				[-1, -1],
				[-1, -1],
				[-1, -1],
			],
			x1: -1,
			y1: -1,
			x2: 2,
			y2: 1,
		}
		try {
			await circuit.calculateWitness(input)
			assert(false, 'Should have failed')
		} catch (err) {
			assert(err.message.includes('Assert Failed'))
		}
	})

	/**
		[[0,0], [1,0], [2,0],
		 [0,1], [1,1], [2,1],
		 [0,2], [1,2], [2,2]]
	 */
	it('Should move or stay put', async function () {
		const board = [
			[0, 0],
			[1, 0],
			[2, 0],
			[0, 1],
			[1, 1],
			[2, 1],
			[0, 2],
			[1, 2],
			[2, 2],
		]

		const moves = [
			[0, 0],
			[1, 0],
			[0, 1],
			[-1, 0],
			[0, -1],
		]

		for (let i = 0; i < board.length; i++) {
			const x1 = board[i][0]
			const y1 = board[i][1]

			for (let j = 0; j < moves.length; j++) {
				const x2 = x1 + moves[j][0]
				const y2 = y1 + moves[j][1]
				if (x2 >= 0 && x2 < 3 && y2 >= 0 && y2 < 3) {
					// console.log('x1:', x1, 'y1:', y1, 'x2:', x2, 'y2:', y2)
					try {
						await circuit.calculateWitness({
							paths: [
								[1, 1],
								[2, 1],
								[-1, -1],
								[-1, -1],
								[-1, -1],
							], // no need to check the paths, just make sure that it's not the first move
							x1,
							y1,
							x2,
							y2,
						})
					} catch (err) {
						assert(false, err.message)
					}
				}
			}
		}
	})

	it('Should fail because of invalid move', async function () {
		const board = [
			[0, 0],
			[1, 0],
			[2, 0],
			[0, 1],
			[1, 1],
			[2, 1],
			[0, 2],
			[1, 2],
			[2, 2],
		]

		const moves = [
			[0, 0],
			[1, 0],
			[0, 1],
			[-1, 0],
			[0, -1],
		]

		for (let i = 0; i < board.length; i++) {
			const x1 = board[i][0]
			const y1 = board[i][1]

			for (let j = 0; j < moves.length; j++) {
				const x2 = x1 + moves[j][0]
				const y2 = y1 + moves[j][1]
				if (x2 >= 0 && x2 < 3 && y2 >= 0 && y2 < 3) {
					// adjacent cells
					continue
				}
				try {
					await circuit.calculateWitness({
						paths: [
							[1, 1],
							[2, 1],
							[-1, -1],
							[-1, -1],
							[-1, -1],
						], // no need to check the paths, just make sure that it's not the first move
						x1,
						y1,
						x2,
						y2,
					})
				} catch (err) {
					assert(err.message.includes('Assert Failed'))
				}
			}
		}
	})
})
