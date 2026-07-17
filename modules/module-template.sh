#!/usr/bin/env bash

module_description() { printf '%s\n' "Describe this deployment stage"; }
module_check() { return 1; }
module_apply() { fatal "module_apply is not implemented"; }
module_verify() { return 1; }

