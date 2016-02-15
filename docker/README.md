You have to modify the IP address in static/setup.sh and static/run-tests.sh to target the cluster
you wish to test before you build the docker container with 'docker build .'

Run 'docker ps' and copy'n'paste the latest imageid..you can run the container by entering
'docker run -it <imageid> /bin/bash'. This will get you a shell prompt where you have to run the following steps:

1. Change into the cli-tests directory
2. Run ./setup.sh
3. Run ./run-tests.sh

This process will take approximately 1.5 hrs
