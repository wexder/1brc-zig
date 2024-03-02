# 1BRC-zig

This is based on the challenge here: https://github.com/gunnarmorling/1brc/.

> The One Billion Row Challenge (1BRC) is a fun exploration of how far modern Java can be pushed for aggregating one billion rows from a text file. 
> Grab all your (virtual) threads, reach out to SIMD, optimize your GC, or pull any other trick, and create the fastest implementation for solving this task!

I decided to implement this in Zig as a learning experience.

# Baseline
```
Executed in    5.76 secs    fish           external
   usr time   37.81 secs  129.00 micros   37.81 secs
   sys time   10.11 secs  526.00 micros   10.11 secs
```

