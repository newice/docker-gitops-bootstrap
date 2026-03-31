## Overview

This repository provides a **bootstrap and reference implementation** for running a multi-host Docker environment based on **Docker Compose stacks**.

It is designed to:
- Initialize new hosts via shell-based bootstrap scripts
- Provide reusable stack templates and infrastructure blueprints
- Enable GitOps-style deployments using a CI/CD pipeline
- Maintain a consistent structure across multiple Docker hosts

## Quickstart 
'''bash
curl -sSL https://raw.githubusercontent.com/newice/docker-gitops-bootstrap/main/bootstrap-docker-host.sh | bash
'''

## Key Characteristics

- **Docker Compose only** — no Kubernetes, no Swarm, no orchestrator
- **Stack-based structure** — one service group per folder
- **Multi-host ready** — designed for distributed environments
- **GitOps workflow** — deployments driven via version control and CI
- **Bootstrap-first** — new hosts can be provisioned from scratch

## What This Repo Is

- A starting point for new Docker hosts
- A library of Compose stack patterns and templates
- A reference architecture for managing containerized services across hosts

## What This Repo Is Not

- Not a Kubernetes distribution
- Not a Docker Swarm setup
- Not a full platform or PaaS

## Typical Use Case

1. Provision a new host
2. Run the bootstrap script to install Docker and prepare the system
3. Connect the host to your CI/CD pipeline
4. Deploy stacks from this repository

This approach prioritizes **simplicity, transparency, and control** over orchestration complexity.
