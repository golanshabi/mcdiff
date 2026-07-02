APP_NAME := mcdiff
CLI_NAME := mcdiff
CLI := Scripts/$(CLI_NAME)
APP := build/$(APP_NAME).app
BIN := $(APP)/Contents/MacOS/$(APP_NAME)
LIBGIT2 ?= /opt/homebrew/opt/libgit2
LOGGING ?= 1
BUILD_MODE := logging
CXX := clang++
ifeq ($(LOGGING),0)
BUILD_MODE := logless
CXX_LOGGING_FLAGS := -DMCD_LOGGING_DISABLED
SWIFT_LOGGING_FLAGS := -D MCD_LOGGING_DISABLED
endif
CXXFLAGS := -std=c++17 -I$(LIBGIT2)/include $(CXX_LOGGING_FLAGS)
SWIFTFLAGS := $(SWIFT_LOGGING_FLAGS)
LDFLAGS := -L$(LIBGIT2)/lib -Wl,-rpath,$(LIBGIT2)/lib
SWIFT_LDFLAGS := -L$(LIBGIT2)/lib -Xlinker -rpath -Xlinker $(LIBGIT2)/lib
OBJ_DIR := build/$(BUILD_MODE)
TEST_BIN := $(OBJ_DIR)/CoreTests
SWIFT_TEST_BIN := $(OBJ_DIR)/SwiftTests
SWIFT_TEST_FILES := \
	Tests/SwiftTests.swift \
	Tests/SwiftTestHelpers.swift \
	Tests/SwiftBridgeTests.swift \
	Tests/SwiftWindowRenderingTests.swift \
	Tests/SwiftMergeEditingTests.swift \
	Tests/SwiftGitAndScrollingTests.swift
SWIFT_TEST_APP_FILES := \
	App/Logger.swift \
	App/PaneViews.swift \
	App/MainWindowController.swift \
	App/MainWindowController+Rendering.swift \
	App/MainWindowController+MergeEditing.swift \
	App/MainWindowController+Git.swift \
	App/MainWindowController+HorizontalScrolling.swift \
	App/MainWindowController+Utilities.swift

$(OBJ_DIR)/.dir:
	mkdir -p $(OBJ_DIR)
	touch $(OBJ_DIR)/.dir

FORCE:

$(BIN): FORCE App/*.swift Bridge/* Core/* | $(OBJ_DIR)/.dir
	mkdir -p $(APP)/Contents/MacOS
	printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>$(APP_NAME)</string><key>CFBundleIdentifier</key><string>local.$(APP_NAME)</string><key>CFBundleName</key><string>$(APP_NAME)</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > $(APP)/Contents/Info.plist
	$(CXX) $(CXXFLAGS) -c Core/Logger.cpp -o $(OBJ_DIR)/Logger.o
	$(CXX) $(CXXFLAGS) -c Core/DiffEngine.cpp -o $(OBJ_DIR)/DiffEngine.o
	$(CXX) $(CXXFLAGS) -c Core/ConflictParser.cpp -o $(OBJ_DIR)/ConflictParser.o
	$(CXX) $(CXXFLAGS) -c Core/MergeBuilder.cpp -o $(OBJ_DIR)/MergeBuilder.o
	$(CXX) $(CXXFLAGS) -c Bridge/DiffBridge.mm -o $(OBJ_DIR)/DiffBridge.o
	swiftc $(SWIFTFLAGS) App/*.swift $(OBJ_DIR)/Logger.o $(OBJ_DIR)/DiffEngine.o $(OBJ_DIR)/ConflictParser.o $(OBJ_DIR)/MergeBuilder.o $(OBJ_DIR)/DiffBridge.o -module-cache-path build/ModuleCache -import-objc-header Bridge/DiffBridge.h -framework AppKit $(SWIFT_LDFLAGS) -lgit2 -lc++ -o $(BIN)

build: $(BIN)

run: build
	open $(APP)

launcher:
	@echo "$(CLI)"

$(TEST_BIN): Tests/CoreTests.cpp Core/* | $(OBJ_DIR)/.dir
	$(CXX) $(CXXFLAGS) Tests/CoreTests.cpp Core/Logger.cpp Core/DiffEngine.cpp Core/ConflictParser.cpp Core/MergeBuilder.cpp $(LDFLAGS) -lgit2 -o $(TEST_BIN)

$(SWIFT_TEST_BIN): $(SWIFT_TEST_FILES) $(SWIFT_TEST_APP_FILES) Bridge/* Core/* | $(OBJ_DIR)/.dir
	$(CXX) $(CXXFLAGS) -c Core/Logger.cpp -o $(OBJ_DIR)/SwiftTestLogger.o
	$(CXX) $(CXXFLAGS) -c Core/DiffEngine.cpp -o $(OBJ_DIR)/SwiftTestDiffEngine.o
	$(CXX) $(CXXFLAGS) -c Core/ConflictParser.cpp -o $(OBJ_DIR)/SwiftTestConflictParser.o
	$(CXX) $(CXXFLAGS) -c Core/MergeBuilder.cpp -o $(OBJ_DIR)/SwiftTestMergeBuilder.o
	$(CXX) $(CXXFLAGS) -c Bridge/DiffBridge.mm -o $(OBJ_DIR)/SwiftTestDiffBridge.o
	swiftc $(SWIFTFLAGS) $(SWIFT_TEST_FILES) $(SWIFT_TEST_APP_FILES) $(OBJ_DIR)/SwiftTest*.o -module-cache-path build/ModuleCache -import-objc-header Bridge/DiffBridge.h -framework AppKit $(SWIFT_LDFLAGS) -lgit2 -lc++ -o $(SWIFT_TEST_BIN)

test: $(TEST_BIN) $(SWIFT_TEST_BIN)
	$(TEST_BIN)
	$(SWIFT_TEST_BIN)

clean:
	rm -rf build

.PHONY: FORCE build run launcher test clean
