set terminal pdf dashed noenhanced size 3.5in,1.5in
set output "fig/bench.pdf"

set style data histogram
set style histogram cluster gap 1
set rmargin at screen .95

set xrange [-1:4.5]
set yrange [0:*]
set grid y
set ylabel "Relative througput"
set ytics scale 0.5,0 nomirror
set xtics scale 0,0
set key top right
set style fill solid 1 border rgb "black"

set label 'file/s' at (0.15 -4./7),1 right rotate by 90 offset character 0,0
set label 'MB/s' at (1.15 -4./7),1 right rotate by 90 offset character 0,0
set label 'app/s' at (2.15 -4./7),1 right rotate by 90 offset character 0,0

plot "data/bench.data" \
        using ($2/$2):xtic(1) title col lc rgb '#b6d7a8' lt 1, \
     '' using ($3/$2):xtic(1) title col lc rgb '#3a81ba' lt 1, \
     '' using ($4/$2):xtic(1) title col lc rgb '#cc0000' lt 1, \
