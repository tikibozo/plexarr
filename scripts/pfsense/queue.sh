#!/bin/tcsh
while (1)
    netstat -Lan | grep -v "0/0" | grep -v "Current" | grep -v "Proto" >> queue.txt	
end

