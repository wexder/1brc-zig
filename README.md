# 1BRC-zig

This is based on the challenge here: https://github.com/gunnarmorling/1brc/.

> The One Billion Row Challenge (1BRC) is a fun exploration of how far modern Java can be pushed for aggregating one billion rows from a text file. 
> Grab all your (virtual) threads, reach out to SIMD, optimize your GC, or pull any other trick, and create the fastest implementation for solving this task!

I decided to implement this in Zig as a learning experience.

# Final result
```
./zig-out/bin/1brc-zig measurements.txt  60.64s user 0.91s system 1014% cpu 6.067 total
```

