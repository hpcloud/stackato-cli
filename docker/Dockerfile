FROM ubuntu:14.04
MAINTAINER Kamen MacKay "kamenm@activestate.com"
ENV PATH /atcl/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded/bin/:/bin/stackato-3.2.1-linux-glibc2.3-x86_64:$PATH
ENV TERM xterm
RUN "apt-get" "update"
RUN "apt-get" "-y" "install" "unzip" "time" "nano"
RUN "apt-get" "clean"
ADD http://stackato.nas2.stackato.com/Client/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded.tar.gz /atcl/
ADD http://stackato.nas2.stackato.com/Client/GoldBits/2015-11-18-3.2.4_RC0/stackato-3.2.4-linux-glibc2.3-x86_64.zip /client/
ADD http://stackato.nas2.stackato.com/Client/GoldBits/2015-11-18-3.2.4_RC0/internal/cli-tests.zip /cli-tests.zip
RUN "unzip" "/cli-tests.zip"
COPY fetch/fetch/ /fetch/
RUN "unzip" "client/stackato-3.2.4-linux-glibc2.3-x86_64.zip" "-d" "/bin"
RUN "cp" "/bin/stackato-3.2.4-linux-glibc2.3-x86_64/stackato" "/bin/"
RUN "tar" "-xvzf" "/atcl/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded.tar.gz" 
RUN "/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded/install.sh" "--directory" "/atcl/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded/"
RUN "/atcl/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded/bin/teacup" "install" "try"
RUN "/atcl/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded/bin/teacup" "install" "fileutil"
RUN "/atcl/ActiveTcl8.5.18.0.298892-linux-x86_64-threaded/bin/teacup" "install" "lexec"
RUN "cd" "fetch"
RUN "tclsh" "fetch/kettle" "-f" "fetch/build.tcl" "install"
COPY /static/setup.sh /cli-tests/setup.sh
COPY /static/run-tests.sh cli-tests/run-tests.sh
COPY /static/clean-tests.sh cli-tests/
COPY /static/start.sh /
RUN "chmod" "+x" "/start.sh"
VOLUME ["/cli-tests"]
CMD ["/start.sh"]
