#!/usr/bin/env python3
from setuptools import setup, find_packages

setup(
    name='rapidapi-setup',
    version='1.0',
    packages=find_packages(),
    install_requires=[
        'requests',
        'python-dotenv'
    ]
)