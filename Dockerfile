FROM jupyter/scipy-notebook


USER root

# Images
RUN apt-get update &&\
    apt-get install -y libjpeg-dev \
                       zlib1g-dev \
                       libpng12-dev \
                       python-pip \
                       wget \
                       vim \
                       libkrb5-dev \
                       libxml2-dev \
                       libxslt-dev \
                       libjpeg-dev \
                       zlib1g-dev \
                       libpng12-dev \
                       libx11-dev

# R pre-requisites
RUN apt-get install -y --no-install-recommends \
    fonts-dejavu \
    gfortran \
    gcc && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Upgrade pip2
RUN python2 -m pip install --upgrade pip

# JUlia
ENV JULIA_PKGDIR=/opt/julia

#Spark
ENV APACHE_SPARK_VERSION 2.1.1
ENV HADOOP_VERSION 2.7

# RSpark config
ENV R_LIBS_USER $SPARK_HOME/R/lib


# Julia dependencies
# install Julia packages in /opt/julia instead of $HOME
RUN echo "deb http://ppa.launchpad.net/staticfloat/juliareleases/ubuntu trusty main" > /etc/apt/sources.list.d/julia.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3D3D3ACC && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    julia \
    libnettle4 && apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Show Julia where conda libraries are \
    echo "push!(Libdl.DL_LOAD_PATH, \"$CONDA_DIR/lib\")" >> /usr/etc/julia/juliarc.jl && \
    # Create JULIA_PKGDIR \
    mkdir $JULIA_PKGDIR && \
    chown -R $NB_USER:users $JULIA_PKGDIR


# Temporarily add jessie backports to get openjdk 8, but then remove that source
RUN echo 'deb http://cdn-fastly.deb.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list && \
    apt-get -y update && \
    apt-get install --no-install-recommends -t jessie-backports -y openjdk-8-jre-headless ca-certificates-java && \
    rm /etc/apt/sources.list.d/jessie-backports.list && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN cd /tmp && \
        wget -q http://d3kbcqa49mib13.cloudfront.net/spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz && \
        echo "4b6427ca6dc6f888b21bff9f9a354260af4a0699a1f43caabf58ae6030951ee5fa8b976497aa33de7e4ae55609d47a80bfe66dfc48c79ea28e3e5b03bdaaba11 *spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" | sha512sum -c - && \
        tar xzf spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz -C /usr/local && \
        rm spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz
RUN cd /usr/local && ln -s spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} spark


# Mesos dependencies
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF && \
    DISTRO=debian && \
    CODENAME=jessie && \
    echo "deb http://repos.mesosphere.io/${DISTRO} ${CODENAME} main" > /etc/apt/sources.list.d/mesosphere.list && \
    apt-get -y update && \
    apt-get --no-install-recommends -y --force-yes install mesos=1.2\* && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


# Spark and Mesos config
ENV SPARK_HOME /usr/local/spark
ENV PYTHONPATH $SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.4-src.zip
ENV MESOS_NATIVE_LIBRARY /usr/local/lib/libmesos.so
ENV SPARK_OPTS --driver-java-options=-Xms1024M --driver-java-options=-Xmx4096M --driver-java-options=-Dlog4j.logLevel=info



USER $NB_USER

# R packages including IRKernel which gets installed globally.
RUN conda config --system --add channels r && \
    conda install --quiet --yes \
    'rpy2=2.8*' \
    'r-base=3.3.2' \
    'r-irkernel=0.7*' \
    'r-plyr=1.8*' \
    'r-devtools=1.12*' \
    'r-tidyverse=1.0*' \
    'r-shiny=0.14*' \
    'r-rmarkdown=1.2*' \
    'r-forecast=7.3*' \
    'r-rsqlite=1.1*' \
    'r-reshape2=1.4*' \
    'r-nycflights13=0.2*' \
    'r-caret=6.0*' \
    'r-rcurl=1.95*' \
    'r-crayon=1.3*' \
    'r-ggplot2=2.2*' \
    'r-sparklyr=0.5*' \
    'r-randomforest=4.6*' && conda clean -tipsy

# Add Julia packages
# Install IJulia as jovyan and then move the kernelspec out
# to the system share location. Avoids problems with runtime UID change not
# taking effect properly on the .local folder in the jovyan home dir.
RUN julia -e 'Pkg.init()' && \
    julia -e 'Pkg.update()' && \
    julia -e 'Pkg.add("HDF5")' && \
    julia -e 'Pkg.add("Gadfly")' && \
    julia -e 'Pkg.add("RDatasets")' && \
    julia -e 'Pkg.add("IJulia")' && \
    # Precompile Julia packages \
    julia -e 'using HDF5' && \
    julia -e 'using Gadfly' && \
    julia -e 'using RDatasets' && \
    julia -e 'using IJulia' && \
    # move kernelspec out of home \
    mv $HOME/.local/share/jupyter/kernels/julia* $CONDA_DIR/share/jupyter/kernels/ && \
    chmod -R go+rx $CONDA_DIR/share/jupyter && \
    rm -rf $HOME/.local

# Apache Toree kernel
RUN pip --no-cache-dir install https://dist.apache.org/repos/dist/dev/incubator/toree/0.2.0/snapshots/dev1/toree-pip/toree-0.2.0.dev1.tar.gz
RUN jupyter toree install --sys-prefix

# Spylon-kernel
RUN conda install --quiet --yes 'spylon-kernel=0.4*' && \
    conda clean -tipsy
RUN python -m spylon_kernel install --sys-prefix


# Install Python 3 Tensorflow
RUN conda install --quiet --yes 'tensorflow=1.0*'

# Install Python 2 Tensorflow
RUN conda install --quiet --yes -n python2 'tensorflow=1.0*'

ADD requirements.txt /home/jovyan/requirements.txt
ADD conda-reqs.txt /home/jovyan/conda-reqs.txt

# Install packages for python3
RUN conda install --quiet --yes --file /home/jovyan/conda-reqs.txt &&\
    python -m pip install -r /home/jovyan/requirements.txt &&\
    python -m pip install newspaper3k

USER root
RUN apt-get update && apt-get install -y libx11-dev
USER $NB_USER

# Install packages for Python2
RUN conda install --quiet --yes -n python2 --file /home/jovyan/conda-reqs.txt
RUN /bin/bash -c "source activate python2 \
    && pip install -r /home/jovyan/requirements.txt \
    && pip install newspaper"

RUN rm /home/jovyan/requirements.txt &&\
    rm /home/jovyan/conda-reqs.txt

# Install NLTK Data
RUN python3 -m nltk.downloader all

# Enable extensions
RUN jupyter nbextension enable --py --sys-prefix widgetsnbextension 


# Enable SparkMagic
RUN EXT_PATH=$(pip show sparkmagic|grep -i location|awk '{print $2'}) &&\
    cd ${EXT_PATH} &&\
    jupyter-kernelspec install --user sparkmagic/kernels/sparkkernel &&\
    jupyter-kernelspec install --user sparkmagic/kernels/pysparkkernel &&\
    jupyter-kernelspec install --user sparkmagic/kernels/pyspark3kernel &&\
    jupyter-kernelspec install --user sparkmagic/kernels/sparkrkernel &&\
    unset EXT_PATH


# Install C++ Kernel
RUN cd /home/jovyan/ &&\
    wget https://root.cern.ch/download/cling/cling_2017-06-22_ubuntu14.tar.bz2 -q &&\
    tar vxf cling_2017-06-22_ubuntu14.tar.bz2 &&\
    rm cling_2017-06-22_ubuntu14.tar.bz2

ENV PATH /home/jovyan/cling_2017-06-22_ubuntu14/bin:$PATH

RUN cd /home/jovyan/cling_2017-06-22_ubuntu14/share/cling/Jupyter/kernel &&\
    pip3 install -e . &&\
    jupyter-kernelspec install --user cling-cpp17 &&\
    jupyter-kernelspec install --user cling-cpp14 &&\
    jupyter-kernelspec install --user cling-cpp11


# Add RISE
RUN cd /home/jovyan &&\
    wget https://github.com/pdonorio/RISE/archive/master.tar.gz -O rise.tar.gz &&\
    tar xvzf rise.tar.gz &&\
    cd RISE-master &&\
    python3 setup.py install

