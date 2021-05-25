# Override these if you like
ERLANG_VERSIONS := 24.0.1 23.3.4.1 22.3.4.19
PLATFORMS := linux/amd64 linux/arm64/v8
DEBIAN_VERSIONS := buster stretch
UBUNTU_VERSIONS := focal bionic xenial trusty
CENTOS_VERSIONS := 8 7

# Don't override these
DEBIANS := $(foreach v,$(DEBIAN_VERSIONS),debian_$(v))
UBUNTUS := $(foreach v,$(UBUNTU_VERSIONS),ubuntu_$(v))
CENTOSES := $(foreach v,$(CENTOS_VERSIONS),centos_$(v))
IMAGE_TAGS := $(DEBIANS) $(UBUNTUS) $(CENTOSES)

DISTS = $(foreach platform,$(subst /,-,$(PLATFORMS)),$(foreach image_tag,$(IMAGE_TAGS),$(foreach erlang,$(ERLANG_VERSIONS),$(platform)_$(image_tag)_$(erlang))))
OTPS = $(foreach v,$(ERLANG_VERSIONS),OTP-$(v))
DOCKERS = $(foreach platform,$(subst /,-,$(PLATFORMS)),$(foreach image_tag,$(IMAGE_TAGS),docker_$(platform)_$(image_tag)))

$(DISTS): PLATFORM = $(subst -,/,$(word 1,$(subst _, ,$@)))
$(DISTS): SAFE_PLATFORM = $(word 1,$(subst _, ,$@))
$(DISTS): IMAGE = $(word 2,$(subst _, ,$@))
$(DISTS): TAG = $(word 3,$(subst _, ,$@))
$(DISTS): ERLANG = $(word 4,$(subst _, ,$@))

.PHONY: $(DISTS)
$(DISTS): $(OTPS) $(DOCKERS)
	@echo "Building erlang ${ERLANG} on ${IMAGE} ${TAG} on ${PLATFORM}"
	docker run --rm \
	--platform $(PLATFORM) \
	-v `pwd`:/opt/in:ro -w /opt \
	"esl:build-${SAFE_PLATFORM}-${IMAGE}-${TAG}" \
	/opt/in/build "$(PLATFORM)" "$(IMAGE)" "$(TAG)" "$(ERLANG)"

OTP-%: OTP = $(word 2,$(subst -, ,$@))
OTP-%:
	@mkdir -p downloads
	@wget --directory-prefix downloads --no-verbose --timestamping \
		https://github.com/erlang/otp/archive/OTP-$(OTP).tar.gz

docker_%: PLATFORM = $(subst -,/,$(word 2,$(subst _, ,$@)))
docker_%: SAFE_PLATFORM = $(word 2,$(subst _, ,$@))
docker_%: IMAGE = $(word 3,$(subst _, ,$@))
docker_%: TAG = $(word 4,$(subst _, ,$@))
docker_%:
	@echo "Building base image ${IMAGE} ${TAG} on ${PLATFORM}"
	export DOCKER_BUILDKIT=1
	@docker build --rm -t "esl:build-${SAFE_PLATFORM}-${IMAGE}-${TAG}" \
	--build-arg platform=${PLATFORM} \
	--build-arg os=${IMAGE} \
	--build-arg os_version=${TAG} \
	-f Dockerfile_${IMAGE}_${TAG} \
	.