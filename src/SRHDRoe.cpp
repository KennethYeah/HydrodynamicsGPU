#include "HydroGPU/SRHDEquation.h"
#include "HydroGPU/SRHDRoe.h"
#include "HydroGPU/HydroGPUApp.h"
#include "Common/File.h"

SRHDRoe::SRHDRoe(HydroGPUApp& app_)
: Super(app_)
{
	equation = std::make_shared<SRHDEquation>(*this);
}

void SRHDRoe::init() {
	Super::init();

	int volume = app.size.s[0] * app.size.s[1] * app.size.s[2];
	primitiveBuffer = clAlloc(sizeof(real) * equation->numStates * volume);
}

std::vector<std::string> SRHDRoe::getProgramSources() {
	std::vector<std::string> sources = Super::getProgramSources();
	sources.push_back(Common::File::read("SRHDRoe.cl"));
	return sources;
}

void SRHDRoe::initKernels() {
	Super::initKernels();
	
	initVariablesKernel = cl::Kernel(program, "initVariables");
	app.setArgs(initVariablesKernel, stateBuffer, primitiveBuffer);

	convertToTexKernel.setArg(0, primitiveBuffer);

	app.setArgs(calcEigenBasisKernel, eigenvaluesBuffer, eigenvectorsBuffer, eigenvectorsInverseBuffer, primitiveBuffer, stateBuffer, gravityPotentialBuffer);
}

void SRHDRoe::resetState() {
	//store Newtonian Euler equation state variables in stateBuffer
	Super::resetState();

	commands.enqueueNDRangeKernel(initVariablesKernel, offsetNd, globalSize, localSize);

	commands.finish();
}

