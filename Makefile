APP_NAME = build
BUILD_DIR = ./build


APP_INCLUDES:=
APP_LINKERS:=
APP_FRAMEWORKS:=
APP_FILES:= ./src/Core/*.m


SHADER_BUILD_DIR = ./src/Shaders/build
SHADER_INTER_FILES:= $(SHADER_BUILD_DIR)/*.ir
SHADER_FILES:= ./src/Shaders/shader.metal

Message ?= $(shell bash -c 'read -p "Message: " message; echo $$message')
Branch ?= $(shell bash -c 'read -p "Branch (main, 2D-Engine, 3D-Engine, 3D-Engine-Physics): " branch; echo $$branch')


all: buildShader buildApp run

build: buildShader buildApp

buildShader:
	xcrun -sdk macosx metal -o $(SHADER_BUILD_DIR)/shader.ir  -c $(SHADER_FILES)
	xcrun -sdk macosx metallib -o $(SHADER_BUILD_DIR)/shader.metallib $(SHADER_INTER_FILES)
	
buildApp:
	clang -O2 -fobjc-arc -fmodules -framework CoreGraphics -framework Metal -framework QuartzCore -framework MetalKit -framework Cocoa -o $(BUILD_DIR)/$(APP_NAME) $(APP_FILES)

#-O0 means no optimization
#-O2 means optimization
run: 
	$(BUILD_DIR)/$(APP_NAME)

clean:
	rm -rf $(BUILD_DIR)/*
	rm -rf $(SHADER_BUILD_DIR)/*

git: add commit push

add: 
	git add .

commit:
	git commit -m "$(Message)"

push :
	git push -u origin $(Branch)
