import { useEffect, useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import Sidebar from './components/Sidebar'
import Dashboard from './components/Dashboard'
import Controls from './components/Controls'
import { generateMetrics, generateSeries } from './lib/mockMetrics'

export default function App() {
  const [active, setActive] = useState('Dashboard')
  const [gameMode, setGameMode] = useState(true)
  const [metrics, setMetrics] = useState(generateMetrics())

  useEffect(() => {
    const id = setInterval(() => setMetrics(generateMetrics()), 1800)
    return () => clearInterval(id)
  }, [])

  const series = useMemo(
    () => ({
      cpu: generateSeries(),
      gpu: generateSeries(),
      ram: generateSeries(24, 35, 82),
      fps: generateSeries(24, 55, 160)
    }),
    [metrics]
  )

  return (
    <div className="min-h-screen p-5 text-hyper-text">
      <div className="mx-auto flex max-w-7xl gap-4">
        <Sidebar active={active} onSelect={setActive} />

        <main className="flex-1 rounded-2xl bg-hyper-panel/70 p-5 shadow-neon">
          <header className="mb-5 flex items-center justify-between">
            <div>
              <h2 className="text-2xl font-semibold">Gaming Control Panel</h2>
              <p className="text-sm text-hyper-muted">Premium controls for performance, profiles, and diagnostics.</p>
            </div>
            <div className="rounded-xl bg-hyper-panelSoft px-3 py-2 text-sm text-hyper-muted">Driver: NVIDIA 570.xx · Vulkan: OK</div>
          </header>

          <AnimatePresence mode="wait">
            <motion.div
              key={active}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.18 }}
            >
              <Dashboard metrics={metrics} series={series} />
              <Controls gameMode={gameMode} setGameMode={setGameMode} />
            </motion.div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  )
}
