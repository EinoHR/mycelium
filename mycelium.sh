xset s off

(
    until ./dbclient; do
        echo "Dbclient crashed with exit code $?.  Respawning.." >&2
        sleep 1
    done
) &> /var/home/mycelium/dbclient.log &

(
    until /usr/lib/jvm/jre-11-openjdk-11.0.18.0.10-1.fc37.x86_64/bin/java -jar mycelium.jar; do
        echo "Java crashed with exit code $?.  Respawning.." >&2
        sleep 1
    done
) &> /var/home/mycelium/openrndr.log

sleep 2
execstack -c /var/home/mycelium/.jSerialComm/2.9.3/libjSerialComm.so