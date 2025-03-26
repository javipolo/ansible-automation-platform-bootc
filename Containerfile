FROM registry.redhat.io/rhel9/rhel-bootc:9.5

# Install dependencies
RUN dnf install -y python3-cryptography python3-psycopg2 \
    && dnf clean all

RUN bootc container lint
