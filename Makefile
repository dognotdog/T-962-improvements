################################################################################
# Makefile to build the improved T-962 firmware without LPCXpresso
#
# Makes a 'build' directory in the root of the project.
################################################################################
BASE_NAME := T-962-controller

SRC_DIR := ./src/
BUILD_DIR := ./build/
TARGET := $(BUILD_DIR)$(BASE_NAME).axf


vpath %.c $(SRC_DIR)
vpath %.o $(BUILD_DIR)
vpath %.d $(BUILD_DIR)


# set GCC_PATH if arm-none-eabi-gcc is not installed in $PATH
ifdef GCC_PATH
CC := $(GCC_PATH)/arm-none-eabi-gcc
SIZE := $(GCC_PATH)/arm-none-eabi-size
OBJCOPY := $(GCC_PATH)/arm-none-eabi-objcopy
else
CC := arm-none-eabi-gcc
SIZE := arm-none-eabi-size
OBJCOPY := arm-none-eabi-objcopy
endif

RM := rm -rf

# Flash tool settings
FLASH_TOOL := ./lpc21isp
FLASH_TTY := /dev/ttyUSB0
FLASH_BAUD := 57600
MCU_CLOCK := 11059

COLOR_GREEN = $(shell echo "\033[0;32m")
COLOR_RED = $(shell echo "\033[0;31m")
COLOR_END = $(shell echo "\033[0m")

# Source files
C_SRCS += $(wildcard $(SRC_DIR)*.c) $(BUILD_DIR)version.c

S_SRCS += $(wildcard $(SRC_DIR)*.s)

OBJS := $(patsubst $(SRC_DIR)%.c,$(BUILD_DIR)%.o,$(C_SRCS)) $(patsubst $(SRC_DIR)%.s,$(BUILD_DIR)%.o,$(S_SRCS))

C_DEPS := $(wildcard *.d)

# Compiler Flags
CPPFLAGS += -DNDEBUG -D__NEWLIB__
CPU = -mcpu=arm7tdmi
CFLAGS += -std=gnu99 $(CPPFLAGS) -Os -g -Wall -Wunused -c -fmessage-length=0 -fno-builtin -ffunction-sections -fdata-sections -flto -ffat-lto-objects $(CPU)
ASFLAGS += -I $(BUILD_DIR) $(CPPFLAGS) $(CPU)
LDFLAGS += -nostdlib -Xlinker -Map="$(BUILD_DIR)$(BASE_NAME).map" -Xlinker --gc-sections -flto -Os $(CPU) --specs=nano.specs -u _printf_float -u _scanf_float -T "$(BASE_NAME).ld"

all: axf

$(BUILD_DIR)version.c: $(BUILD_DIR)tag
	git describe --tag --always --dirty | \
		sed 's/.*/const char* Version_GetGitVersion(void) { return "&"; }/' > $@

# Always regenerate the git version
.PHONY: $(BUILD_DIR)version.c

$(BUILD_DIR)tag:
	mkdir -p $(BUILD_DIR)
	touch $(BUILD_DIR)tag

$(BUILD_DIR)%.o: $(SRC_DIR)%.c $(BUILD_DIR)tag
	@echo 'Building file: $<'
	$(CC) $(CFLAGS) -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@:%.o=%.o)" -MT"$(@:%.o=%.d)" -o "$@" "$<"
	@echo 'Finished building: $(COLOR_GREEN)$<$(COLOR_END)'
	@echo ' '

$(BUILD_DIR)%.o: $(SRC_DIR)%.s $(BUILD_DIR)tag
	@echo 'Building file: $<'
	$(CC) -c -x assembler-with-cpp $(ASFLAGS) -o "$@" "$<"
	@echo 'Finished building: $(COLOR_GREEN)$<$(COLOR_END)'
	@echo ' '


axf: $(OBJS) $(USER_OBJS)
	@echo 'Building target: $@'
	@echo 'Invoking: MCU Linker'
	$(CC) $(LDFLAGS) -o "$(TARGET)" $(OBJS) $(USER_OBJS) $(LIBS)
	@echo 'Finished building target: $(COLOR_GREEN)$@$(COLOR_END)'
	@echo ' '
	$(MAKE) --no-print-directory post-build

clean:
	-$(RM) $(BUILD_DIR)
	-@echo ' '

post-build:
	-@echo 'Performing post-build steps'
	-$(CC) --version
	-$(SIZE) "$(TARGET)";
	-$(OBJCOPY) -v -O ihex "$(TARGET)" "$(BUILD_DIR)$(BASE_NAME).hex"
	-@echo ' '

lpc21isp: $(BUILD_DIR)tag
	-@echo ''
	-@echo 'Downloading lpc21isp 1.97 source from sourceforge'
	wget http://sourceforge.net/projects/lpc21isp/files/lpc21isp/1.97/lpc21isp_197.zip/download -O $(BUILD_DIR)lpc21isp.zip
	unzip -qq -o $(BUILD_DIR)lpc21isp.zip -d $(BUILD_DIR)

	-@echo 'Making lpc21isp'
	$(MAKE) -C $(BUILD_DIR)lpc21isp_197/
	-@echo 'Copy lpc21isp binary to current directory'
	cp $(BUILD_DIR)lpc21isp_197/lpc21isp .
	-@echo ''

flash: axf lpc21isp
	@echo ''
	@echo 'Flashing $(COLOR_GREEN)$(BASE_NAME).hex$(COLOR_END) to $(COLOR_RED)$(FLASH_TTY)$(COLOR_END)'
	$(FLASH_TOOL) "$(BUILD_DIR)$(BASE_NAME).hex" $(FLASH_TTY) $(FLASH_BAUD) $(MCU_CLOCK)

.PHONY: clean dependents
.SECONDARY: post-build

-include ../makefile.targets
