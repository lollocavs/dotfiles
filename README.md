# dotfiles
Dotfiles collections manage by stow.
(Insert instruction to install and use stow)


## Kitty
- Configured with a Catpuccin Themes 
- Font : CaskaydiaCove Nerd Font Mono
- Set background opacity to 0.4 

## Starship
- Configuration with Catpuccin Theme Scheme

## How to install Starship
Here's a quick how-to for installing Starship on Debian:

**1. Install Starship**

```bash
curl -sS https://starship.rs/install.sh | sh
```

**2. Add to your shell**

For **Bash**, add this to the end of `~/.bashrc`:
```bash
eval "$(starship init bash)"
```

For **Zsh**, add this to the end of `~/.zshrc`:
```bash
eval "$(starship init zsh)"
```

**3. Restart your shell**

```bash
exec $SHELL
```

**4. (Optional) Install a Nerd Font**

Starship works best with a Nerd Font for icons. Download one from [nerdfonts.com](https://www.nerdfonts.com/), install it, and set it as your terminal font.

Popular choices: FiraCode Nerd Font, JetBrainsMono Nerd Font, Meslo Nerd Font.

**5. (Optional) Configure**

Create/edit `~/.config/starship.toml` for customization. You can start with a preset:
```bash
starship preset nerd-font-symbols -o ~/.config/starship.toml
```

That's it! Your prompt should now be using Starship.
