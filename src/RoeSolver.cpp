#include "HydroGPU/RoeSolver.h"
#include "Common/Exception.h"
#include "Common/Finally.h"
#include "Macros.h"
#include <OpenGL/gl.h>
#include <fstream>

std::string readFile(std::string filename) {
	std::ifstream f(filename);
	f.seekg(0, f.end);
	size_t len = f.tellg();
	f.seekg(0, f.beg);
	char *buf = new char[len];
	Finally finally([&](){ delete[] buf; });
	f.read(buf, len);
	return std::string(buf, len);
}

RoeSolver::RoeSolver(
	cl_device_id deviceID,
	cl_context context,
	cl_int2 size,
	cl_command_queue commands,
	std::vector<Cell> &cells,
	real2 xmin,
	real2 xmax,
	cl_mem fluidTexMem,
	cl_mem gradientTexMem)
: Solver(deviceID, context, size, commands, cells, xmin, xmax, fluidTexMem, gradientTexMem)
, program(cl_program())
, cellsMem(cl_mem())
, calcEigenDecompositionKernel(cl_kernel())
, calcDeltaQTildeKernel(cl_kernel())
, calcRTildeKernel(cl_kernel())
, calcFluxKernel(cl_kernel())
, updateStateKernel(cl_kernel())
, convertToTexKernel(cl_kernel())
{
	int err = 0;
	
	std::string kernelSource = readFile("res/roe_solver.cl");
	const char *kernelSourcePtr = kernelSource.c_str();
	cl_program program = clCreateProgramWithSource(context, 1, (const char **) &kernelSourcePtr, NULL, &err);
	if (!program) throw Exception() << "Error: Failed to create compute program!";
 
	err = clBuildProgram(program, 0, NULL, "-I res/include", NULL, NULL);
	if (err != CL_SUCCESS) {
		size_t len;
		char buffer[2048];
 
		std::cout << "Error: Failed to build program executable!\n" << std::endl;
		clGetProgramBuildInfo(program, deviceID, CL_PROGRAM_BUILD_LOG, sizeof(buffer), buffer, &len);
		std::cout << buffer << std::endl;
		exit(1);
	}
 
	unsigned int count = size.s[0] * size.s[1];
	cellsMem = clCreateBuffer(context,  CL_MEM_READ_WRITE,  sizeof(Cell) * count, NULL, NULL);
	if (!cellsMem) throw Exception() << "Error: Failed to allocate device memory!";

	err = clEnqueueWriteBuffer(commands, cellsMem, CL_TRUE, 0, sizeof(Cell) * count, &cells[0], 0, NULL, NULL);
	if (err != CL_SUCCESS) {
		std::cout << "Error: Failed to write to source array!\n" << std::endl;
		exit(1);
	}
 
	calcEigenDecompositionKernel = clCreateKernel(program, "calcEigenDecomposition", &err);
	if (!calcEigenDecompositionKernel || err != CL_SUCCESS) throw Exception() << "failed to create kernel";
	
	calcDeltaQTildeKernel = clCreateKernel(program, "calcDeltaQTilde", &err);
	if (!calcDeltaQTildeKernel || err != CL_SUCCESS) throw Exception() << "failed to create kernel";
	
	calcRTildeKernel = clCreateKernel(program, "calcRTilde", &err);
	if (!calcRTildeKernel || err != CL_SUCCESS) throw Exception() << "failed to create kernel";

	calcFluxKernel = clCreateKernel(program, "calcFlux", &err);
	if (!calcFluxKernel || err != CL_SUCCESS) throw Exception() << "failed to create kernel";
	
	updateStateKernel = clCreateKernel(program, "updateState", &err);
	if (!updateStateKernel || err != CL_SUCCESS) throw Exception() << "failed to create kernel";

	convertToTexKernel = clCreateKernel(program, "convertToTex", &err);
	if (!convertToTexKernel || err != CL_SUCCESS) throw Exception() << "failed to create kernel";

	cl_kernel* kernels[] = {
		&calcEigenDecompositionKernel,
		&calcDeltaQTildeKernel,
		&calcRTildeKernel,
		&calcFluxKernel,
		&updateStateKernel,
	};
	std::for_each(kernels, kernels + numberof(kernels), [&](cl_kernel* kernel) {
		err = 0;
		err  = clSetKernelArg(*kernel, 0, sizeof(cl_mem), &cellsMem);
		err |= clSetKernelArg(*kernel, 1, sizeof(cl_uint2), &size.s[0]);
		if (err != CL_SUCCESS) throw Exception() << "Error: Failed to set kernel arguments! " << err;
	});
	
	real dx[DIM];
	for (int i = 0; i < DIM; ++i) {
		dx[i] = (xmax.s[i] - xmin.s[i]) / (float)size.s[i];
	}
	real dt = .00001;
	real2 dt_dx;
	for (int i = 0; i < DIM; ++i) {
		dt_dx.s[i] = dt / dx[i];
	}
	err = clSetKernelArg(calcFluxKernel, 2, sizeof(real2), dt_dx.s);
	if (err != CL_SUCCESS) throw Exception() << "Error: Failed to set kernel arguments! " << err;

	err = clSetKernelArg(updateStateKernel, 2, sizeof(real2), dt_dx.s);
	if (err != CL_SUCCESS) throw Exception() << "Error: Failed to set kernel arguments! " << err;

	err = 0;
	err  = clSetKernelArg(convertToTexKernel, 0, sizeof(cl_mem), &cellsMem);
	err |= clSetKernelArg(convertToTexKernel, 1, sizeof(cl_uint2), &size.s[0]);
	err |= clSetKernelArg(convertToTexKernel, 2, sizeof(cl_mem), &fluidTexMem);
	err |= clSetKernelArg(convertToTexKernel, 3, sizeof(cl_mem), &gradientTexMem);
	if (err != CL_SUCCESS) throw Exception() << "Error: Failed to set kernel arguments! " << err;
}

RoeSolver::~RoeSolver() {
	clReleaseProgram(program);
	clReleaseMemObject(cellsMem);
	clReleaseKernel(calcEigenDecompositionKernel);
	clReleaseKernel(calcDeltaQTildeKernel);
	clReleaseKernel(calcRTildeKernel);
	clReleaseKernel(calcFluxKernel);
	clReleaseKernel(updateStateKernel);
	clReleaseKernel(convertToTexKernel);
}

void RoeSolver::update(
	cl_command_queue commands, 
	cl_mem fluidTexMem, 
	size_t *global_size,
	size_t *local_size)
{
	int err = 0;

	err = clEnqueueNDRangeKernel(commands, calcEigenDecompositionKernel, 2, NULL, global_size, local_size, 0, NULL, NULL);
	if (err) throw Exception() << "failed to execute calcEigenDecompositionKernel";
	
	err = clEnqueueNDRangeKernel(commands, calcDeltaQTildeKernel, 2, NULL, global_size, local_size, 0, NULL, NULL);
	if (err) throw Exception() << "failed to execute calcDeltaQTildeKernel";
	
	err = clEnqueueNDRangeKernel(commands, calcRTildeKernel, 2, NULL, global_size, local_size, 0, NULL, NULL);
	if (err) throw Exception() << "failed to execute calcRTildeKernel";
	
	err = clEnqueueNDRangeKernel(commands, calcFluxKernel, 2, NULL, global_size, local_size, 0, NULL, NULL);
	if (err) throw Exception() << "failed to execute calcFluxKernel";
	
	err = clEnqueueNDRangeKernel(commands, updateStateKernel, 2, NULL, global_size, local_size, 0, NULL, NULL);
	if (err) throw Exception() << "failed to execute updateStateKernel";

	glFlush();
	glFinish();
	clEnqueueAcquireGLObjects(commands, 1, &fluidTexMem, 0, 0, 0);
	
	err = clEnqueueNDRangeKernel(commands, convertToTexKernel, 2, NULL, global_size, local_size, 0, NULL, NULL);
	if (err) throw Exception() << "failed to execute convertToTexKernel";

	clEnqueueReleaseGLObjects(commands, 1, &fluidTexMem, 0, 0, 0);
	clFlush(commands);
	clFinish(commands);
}

