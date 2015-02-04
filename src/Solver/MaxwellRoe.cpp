#include "HydroGPU/Solver/MaxwellRoe.h"
#include "HydroGPU/HydroGPUApp.h"
#include "HydroGPU/Equation/Maxwell.h"
#include "Common/File.h"

namespace HydroGPU {
namespace Solver {

MaxwellRoe::MaxwellRoe(HydroGPUApp& app_)
: Super(app_)
{
	equation = std::make_shared<HydroGPU::Equation::Maxwell>(*this);
}

void MaxwellRoe::init() {
	Super::init();
	addSourceKernel = cl::Kernel(program, "addSource");
	addSourceKernel.setArg(1, stateBuffer);
}

std::vector<std::string> MaxwellRoe::getProgramSources() {
	std::vector<std::string> sources = Super::getProgramSources();
	sources.push_back(Common::File::read("MaxwellRoe.cl"));
	return sources;
}

void MaxwellRoe::calcDeriv(cl::Buffer derivBuffer) {
	Super::calcDeriv(derivBuffer);
	addSourceKernel.setArg(0, derivBuffer);
	commands.enqueueNDRangeKernel(addSourceKernel, offsetNd, globalSize, localSize);
}

}
}
