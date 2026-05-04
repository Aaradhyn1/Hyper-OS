import { motion } from 'framer-motion'

export default function Controls({ gameMode, setGameMode }) {
  return (
    <section className="mt-5 grid grid-cols-1 gap-4 lg:grid-cols-2">
      <motion.div layout className="rounded-2xl bg-hyper-panel p-5">
        <h3 className="text-lg font-semibold">Game Mode</h3>
        <p className="mt-1 text-sm text-hyper-muted">Toggle system-wide gaming performance mode.</p>
        <button
          onClick={() => setGameMode(!gameMode)}
          className={`mt-4 w-52 rounded-full px-5 py-3 font-semibold transition ${
            gameMode
              ? 'bg-hyper-cyan text-black shadow-neon'
              : 'bg-hyper-panelSoft text-hyper-text'
          }`}
        >
          {gameMode ? 'Game Mode: ON' : 'Game Mode: OFF'}
        </button>
      </motion.div>

      <motion.div layout className="rounded-2xl bg-hyper-panel p-5">
        <h3 className="text-lg font-semibold">Performance Controls</h3>
        <div className="mt-3 space-y-3 text-sm">
          <label className="block">
            CPU Governor
            <select className="mt-1 w-full rounded-lg bg-hyper-panelSoft p-2 text-hyper-text">
              <option>performance</option>
              <option>schedutil</option>
            </select>
          </label>
          <label className="block">
            I/O Scheduler
            <select className="mt-1 w-full rounded-lg bg-hyper-panelSoft p-2 text-hyper-text">
              <option>mq-deadline</option>
              <option>bfq</option>
            </select>
          </label>
        </div>
      </motion.div>
    </section>
  )
}
