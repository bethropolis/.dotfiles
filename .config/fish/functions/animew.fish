function animew --wraps='bash /home/bet/.config/anime/aniwatch-dl.sh -t 8 -T 300 -o dub -r 1080 -a'
    # This function passes all its arguments ($argv) to the script.
    # The hardcoded options come first, then all the user-provided ones.
    bash "$HOME/.config/anime/aniwatch-dl.sh" \
        -t 8 \
        -T 300 \
        -o dub \
        -r 1080 \
        -a \
        $argv
end
