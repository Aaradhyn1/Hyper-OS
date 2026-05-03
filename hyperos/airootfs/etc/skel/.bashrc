# Hyper OS shell identity
export PS1='\[\e[38;5;45m\]hyper\[\e[0m\]@\[\e[38;5;99m\]\h\[\e[0m\]:\w\$ '
alias ll='ls -lah --color=auto'
if command -v fastfetch >/dev/null 2>&1 && [ -z "${SSH_CONNECTION:-}" ]; then
  fastfetch --config /etc/xdg/fastfetch/config.jsonc
fi
