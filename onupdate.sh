#!/bin/sh
f="$1";
c="$2";
s="stat -f %m $f";
t=`$s`;
while [ 1 ];
do
	if [ $t -eq `$s` ]; then
		sleep 1;
	else
		echo "$c";
		echo `$c`;
		t=`$s`;
	fi;
done
