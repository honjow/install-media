export ZSH="$HOME/.oh-my-zsh"

rm -rf "$ZSH/custom/plugins"
rm -rf "$ZSH/custom/themes"
ln -sf "$HOME/.oh-my-zsh-custom/plugins" "$ZSH/custom/plugins"
ln -sf "$HOME/.oh-my-zsh-custom/themes" "$ZSH/custom/themes"

ZSH_THEME="ys"

plugins=(git sudo z fast-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

./install.sh