#! /bin/bash
cd linux.git
for((i=0;i=100000;i++))
{
	make -j8
	sleep 10;
}
