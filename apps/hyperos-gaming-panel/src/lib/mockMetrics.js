export function generateSeries(points = 24, min = 25, max = 90) {
  const values = []
  for (let i = 0; i < points; i += 1) {
    values.push({
      t: i,
      value: Math.round(min + Math.random() * (max - min))
    })
  }
  return values
}

export function generateMetrics() {
  return {
    cpu: Math.round(20 + Math.random() * 70),
    gpu: Math.round(25 + Math.random() * 70),
    ram: Math.round(30 + Math.random() * 50),
    fps: Math.round(55 + Math.random() * 90)
  }
}
