/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        hyper: {
          bg: '#0b0f14',
          panel: '#131a22',
          panelSoft: '#1a2430',
          text: '#e9f1ff',
          muted: '#9ab0cc',
          cyan: '#39d5ff',
          purple: '#8f5dff',
          danger: '#ff5f7a',
          ok: '#47f5b2'
        }
      },
      boxShadow: {
        neon: '0 0 30px rgba(57, 213, 255, 0.22)',
        purple: '0 0 30px rgba(143, 93, 255, 0.18)'
      },
      borderRadius: {
        '2xl': '1rem'
      }
    }
  },
  plugins: []
}
