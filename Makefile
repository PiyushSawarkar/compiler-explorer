default: run

help: # with thanks to Ben Rady
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

export XZ_OPT=-1 -T 0

# If you see "node-not-found" then you need to depend on node-installed.
NODE:=node-not-found
NPM:=npm-not-found

# These 'find' scripts cache their results in a dotfile.
# Doing it this way instead of NODE:=$(shell etc/script/find-node) means
# if they fail, they stop the make process. As best I can tell there's no
# way to get make to fail if a sub-shell command fails.
.node-bin: etc/scripts/find-node
	@etc/scripts/find-node .node-bin

# All targets that need node must depend on this to ensure the NODE variable
# is appropriately set, and that PATH is updated.
node-installed: .node-bin
	@$(eval NODE:=$(shell cat .node-bin))
	@$(eval NPM:=$(shell dirname $(shell cat .node-bin))/npm)
	@$(eval PATH=$(shell dirname $(realpath $(NODE))):${PATH})

info: node-installed ## print out some useful variables
	@echo Using node from $(NODE)
	@echo Using npm from $(NPM)
	@echo PATH is $(PATH)

.PHONY: clean run test run-amazon
.PHONY: dist lint prereqs node_modules travis-dist
prereqs: node_modules webpack

NODE_MODULES=.npm-updated
$(NODE_MODULES): package.json | node-installed
	$(NPM) install $(NPM_FLAGS)
	@touch $@

webpack: $(NODE_MODULES)  ## Runs webpack (useful only for debugging webpack)
	./node_modules/webpack-cli/bin/cli.js ${WEBPACK_ARGS}

lint: $(NODE_MODULES)  ## Ensures everything matches code conventions
	$(NPM) run lint

node_modules: $(NODE_MODULES)
webpack: $(WEBPACK)

test: $(NODE_MODULES)  ## Runs the tests
	$(NPM) run test
	@echo Tests pass

check: $(NODE_MODULES) test lint  ## Runs all checks required before committing

clean:  ## Cleans up everything
	rm -rf node_modules .*-updated .*-bin out static/dist static/vs

# Don't use $(NODE) ./node_modules/<path to node_module> as sometimes that's not actually a node script. Instead, rely
# on PATH ensuring "node" is found in our distribution first.
run: export NODE_ENV=LOCAL WEBPACK_ARGS="-p"
run: prereqs  ## Runs the site normally
	./node_modules/.bin/supervisor -w app.js,lib,etc/config -e 'js|node|properties' --exec $(NODE) $(NODE_ARGS) -- ./app.js $(EXTRA_ARGS)

dev: export NODE_ENV=DEV
dev: prereqs install-git-hooks ## Runs the site as a developer; including live reload support and installation of git hooks
	./node_modules/.bin/supervisor -w app.js,lib,etc/config -e 'js|node|properties' --exec $(NODE) $(NODE_ARGS) -- ./app.js $(EXTRA_ARGS)

debug: export NODE_ENV=DEV
debug: prereqs install-git-hooks ## Runs the site as a developer with full debugging; including live reload support and installation of git hooks
	./node_modules/.bin/supervisor -w app.js,lib,etc/config -e 'js|node|properties' --exec $(NODE) $(NODE_ARGS) -- ./app.js --debug $(EXTRA_ARGS)

HASH := $(shell git rev-parse HEAD)
dist: export WEBPACK_ARGS=-p
dist: prereqs  ## Creates a distribution
	rm -rf out/dist/
	mkdir -p out/dist
	cp -r static/dist/ out/dist/
	cp -r static/policies/ out/dist/
	echo ${HASH} > out/dist/git_hash

travis-dist: dist  ## Creates a distribution as if we were running on travis
	tar --exclude './.travis-compilers' --exclude './.git' --exclude './static' --exclude './.github' --exclude './.idea' --exclude './.nyc_output' --exclude './coverage' --exclude './test' --exclude './docs' -Jcf /tmp/ce-build.tar.xz .
	rm -rf out/dist-bin
	mkdir -p out/dist-bin
	mv /tmp/ce-build.tar.xz out/dist-bin/${TRAVIS_BUILD_NUMBER}.tar.xz
	echo ${HASH} > out/dist-bin/${TRAVIS_BUILD_NUMBER}.txt

install-git-hooks:  ## Install git hooks that will ensure code is linted and tests are run before allowing a check in
	ln -sf $(shell pwd)/etc/scripts/pre-commit .git/hooks/pre-commit
.PHONY: install-git-hooks

changelog:  ## Create the changelog
	python ./etc/scripts/changelog.py

policies:
	python ./etc/scripts/politic.py

.PHONY: changelog
