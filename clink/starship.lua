local home = os.getenv("USERPROFILE") or os.getenv("HOME")
local starship_config_path = home .. "\\.config\\starship.toml"
os.setenv("STARSHIP_CONFIG", starship_config_path)
load(io.popen('starship init cmd'):read('*a'))()
