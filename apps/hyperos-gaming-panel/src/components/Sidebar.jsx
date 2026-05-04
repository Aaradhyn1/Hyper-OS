const nav = ['Dashboard', 'Game Profiles', 'Performance', 'Drivers', 'Logs']

export default function Sidebar({ active, onSelect }) {
  return (
    <aside className="w-60 rounded-2xl bg-hyper-panel/95 p-4 shadow-purple">
      <h1 className="mb-6 text-xl font-semibold tracking-wide text-hyper-cyan">Hyper OS</h1>
      <div className="space-y-2">
        {nav.map((item) => (
          <button
            key={item}
            onClick={() => onSelect(item)}
            className={`w-full rounded-xl px-3 py-2 text-left text-sm glow-hover ${
              active === item
                ? 'bg-hyper-panelSoft text-hyper-text border border-hyper-cyan/30'
                : 'text-hyper-muted hover:bg-hyper-panelSoft/70'
            }`}
          >
            {item}
          </button>
        ))}
      </div>
    </aside>
  )
}
