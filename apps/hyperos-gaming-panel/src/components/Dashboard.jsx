import { motion } from 'framer-motion'
import { AreaChart, Area, ResponsiveContainer } from 'recharts'

function MetricCard({ label, value, unit, data, color }) {
  return (
    <motion.div
      layout
      whileHover={{ y: -2, scale: 1.01 }}
      className="glow-hover rounded-2xl bg-hyper-panel p-4"
    >
      <div className="mb-2 text-xs uppercase tracking-wider text-hyper-muted">{label}</div>
      <div className="mb-3 text-3xl font-semibold" style={{ color }}>{value}{unit}</div>
      <div className="h-16 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data}>
            <Area type="monotone" dataKey="value" stroke={color} fill={color} fillOpacity={0.25} strokeWidth={2} />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </motion.div>
  )
}

export default function Dashboard({ metrics, series }) {
  return (
    <section className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="CPU Usage" value={metrics.cpu} unit="%" data={series.cpu} color="#39d5ff" />
      <MetricCard label="GPU Usage" value={metrics.gpu} unit="%" data={series.gpu} color="#8f5dff" />
      <MetricCard label="RAM Usage" value={metrics.ram} unit="%" data={series.ram} color="#47f5b2" />
      <MetricCard label="FPS" value={metrics.fps} unit="" data={series.fps} color="#ffd166" />
    </section>
  )
}
