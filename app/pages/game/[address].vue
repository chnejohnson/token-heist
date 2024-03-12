<script setup lang="ts">
import { ws, sendRoomCount } from '~/core/websocket'
import { Channel, type ServerSendMsg, type SSRoomCount } from '@token-heist/backend/src/types/socketTypes'

const route = useRoute()
const address = route.params.address as string

if (!address) {
	navigateTo('/')
}

// ----------------------- feat: lobby online count -----------------------

const roomCount = ref(0)

if (process.client) {
	onMounted(() => {
		if (ws.readyState === ws.OPEN) {
			sendRoomCount(address, true)
		}
	})

	ws.onmessage = event => {
		const msg: ServerSendMsg<SSRoomCount> = JSON.parse(event.data)
		switch (msg.type) {
			case Channel.RoomCount:
				roomCount.value = msg.data.count
				break
		}
	}

	onUnmounted(() => {
		sendRoomCount(address, false)
	})
}

// ----------------------- feat: tic-tac-toe -----------------------

const player = ref('X')
const board = ref([
	['', '', ''],
	['', '', ''],
	['', '', ''],
])

const CalculateWinner = board => {
	const lines = [
		[0, 1, 2],
		[3, 4, 5],
		[6, 7, 8],
		[0, 3, 6],
		[1, 4, 7],
		[2, 5, 8],
		[0, 4, 8],
		[2, 4, 6],
	]

	for (let i = 0; i < lines.length; i++) {
		const [a, b, c] = lines[i]

		if (board[a] && board[a] === board[b] && board[a] === board[c]) {
			return board[a]
		}
	}

	return null
}

const winner = computed(() => CalculateWinner(board.value.flat()))

const MakeMove = (x, y) => {
	if (winner.value) return

	if (board.value[x][y]) return

	board.value[x][y] = player.value

	player.value = player.value === 'X' ? 'O' : 'X'
}

const ResetGame = () => {
	board.value = [
		['', '', ''],
		['', '', ''],
		['', '', ''],
	]
	player.value = 'X'
}
</script>

<template>
	<main class="pt-8 text-center">
		<NuxtLink to="/">
			<h1 class="mb-8 text-3xl font-bold uppercase">Token Heist</h1>
		</NuxtLink>

		<p>{{ roomCount }}</p>

		<h3 class="text-xl mb-4">Player {{ player }}'s turn</h3>

		<div class="flex flex-col items-center mb-8">
			<div v-for="(row, x) in board" :key="x" class="flex">
				<div
					v-for="(cell, y) in row"
					:key="y"
					@click="MakeMove(x, y)"
					:class="`border border-white w-24 h-24 hover:bg-gray-700 flex items-center justify-center material-icons-outlined text-4xl cursor-pointer ${cell === 'X' ? 'text-pink-500' : 'text-blue-400'}`"
				>
					{{ cell === 'X' ? 'close' : cell === 'O' ? 'circle' : '' }}
				</div>
			</div>
		</div>

		<div class="text-center">
			<h2 v-if="winner" class="text-6xl font-bold mb-8">Player '{{ winner }}' wins!</h2>
			<button
				@click="ResetGame"
				class="px-4 py-2 bg-pink-500 rounded uppercase font-bold hover:bg-pink-600 duration-300"
			>
				Reset
			</button>
		</div>
	</main>
</template>

<style></style>