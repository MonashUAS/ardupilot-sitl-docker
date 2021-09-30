FROM ubuntu:focal AS builder

ARG COPTER_TAG=Copter-4.1

# install git 
RUN apt-get update && apt-get install -y git

# Trick to get apt-get to not prompt for timezone in tzdata
ENV DEBIAN_FRONTEND=noninteractive

# Need sudo and lsb-release for the installation prerequisites
# keyboard-configuartion is installed by setup script and hangs on Focal
RUN apt-get install -y sudo lsb-release tzdata keyboard-configuration

# Need USER set so usermod does not fail...
# Install all prerequisites now
ENV USER=user
RUN adduser --disabled-login $USER \
    && echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER \
    && chmod 0440 /etc/sudoers.d/$USER

RUN mkdir /src && chown $USER /src
USER $USER

# Now grab ArduPilot from GitHub
RUN git clone https://github.com/ArduPilot/ardupilot.git /src/ardupilot
WORKDIR /src/ardupilot

# Checkout the latest Copter...
RUN git checkout ${COPTER_TAG}

# Now start build instructions from http://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html
RUN git submodule update --init --recursive

RUN export DEBIAN_FRONTEND=noninteractive && Tools/environment_install/install-prereqs-ubuntu.sh -y

# Continue build instructions from https://github.com/ArduPilot/ardupilot/blob/master/BUILD.md
RUN ./waf distclean
RUN ./waf configure --board sitl
RUN ./waf copter
RUN ./waf rover 
RUN ./waf plane
RUN ./waf sub

# save required SITL package names to file
RUN /bin/bash -c 'source Tools/environment_install/install-prereqs-ubuntu.sh \
    && echo "$SITL_PKGS" > /src/ardupilot/sitl_pkgs.txt'

# save wheels for all python dependencies
RUN sudo mkdir /wheels && sudo chown ${USER} /wheels
RUN pip3 freeze --user > requirements.txt
RUN cat requirements.txt | xargs -n 1 pip3 wheel -w /wheels

FROM ubuntu:focal
ENV DEBIAN_FRONTEND=noninteractive

# some required packages
RUN apt-get update && apt-get install -y procps python-is-python3 dnsutils \
    && rm -rf /var/cache/apt/lists
RUN apt-get purge modemmanager

COPY --from=builder /src/ardupilot /ardupilot
WORKDIR /ardupilot

# install saved SITL dependencies :(
RUN /bin/bash -c "apt-get update && apt-get install -y --no-install-recommends $(cat sitl_pkgs.txt) \
    && rm -rf /var/cache/apt/lists"

# install python dependencies from built wheels (no build tools required)
COPY --from=builder /wheels /wheels
RUN cd /ardupilot && pip install --prefer-binary --find-links=/wheels -r requirements.txt

# TCP 5760 is what the sim exposes by default
EXPOSE 5760/tcp

# Variables for simulator
ENV INSTANCE 0
ENV LAT 42.3898
ENV LON -71.1476
ENV ALT 14
ENV DIR 270
ENV MODEL +
ENV SPEEDUP 1
ENV VEHICLE ArduCopter

# Finally the command
ENTRYPOINT /ardupilot/Tools/autotest/sim_vehicle.py --vehicle ${VEHICLE} -I${INSTANCE} --custom-location=${LAT},${LON},${ALT},${DIR} -w --frame ${MODEL} --no-rebuild --no-mavproxy --speedup ${SPEEDUP}
