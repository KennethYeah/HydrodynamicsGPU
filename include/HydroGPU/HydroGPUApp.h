#pragma once

#include "HydroGPU/Solver.h"
#include "CLApp/CLApp.h"
#include "Config/Config.h"
#include "Tensor/Vector.h"

struct HydroGPUApp : public ::CLApp::CLApp {
	typedef ::CLApp::CLApp Super;

	GLuint gradientTex;
	
	cl::ImageGL gradientTexMem;	//as it is written, data is read from this for mapping values to colors

	std::shared_ptr<Solver> solver;

	//config
	std::string configFilename;
	std::string configString;
	std::string solverName;
	cl_int2 size;
	int doUpdate;	//0 = no, 1 = continuous, 2 = single step
	int maxFrames;	//run this far and pause.  -1 = forever = default
	int currentFrame;
	real2 xmin, xmax;
	bool useFixedDT;
	real fixedDT;
	real cfl;
	int displayMethod;
	float displayScale;
	int boundaryMethod;
	bool useGravity;
	double noise;	//use this to init noise if using the default initState
	double gamma;
	std::shared_ptr<Config::Config> config;
	
	//input
	bool leftButtonDown;
	bool rightButtonDown;
	bool leftShiftDown;
	bool rightShiftDown;
	bool leftGuiDown;
	bool rightGuiDown;
	
	//display
	Tensor::Vector<int,2> screenSize;
	float aspectRatio;

	HydroGPUApp();

	virtual int main(std::vector<std::string> args);
	virtual void init();
	virtual void shutdown();
	virtual void resize(int width, int height);
	virtual void update();
	virtual void sdlEvent(SDL_Event &event);
};
