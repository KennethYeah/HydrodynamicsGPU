//HLLC based on
//http://math.lanl.gov/~shenli/publications/hllc_mhd.pdf
//http://marian.fsik.cvut.cz/~bodnar/PragueSum_2012/Toro_2-HLLC-RiemannSolver.pdf

#include "HydroGPU/Shared/Common.h"

void calcEigenvaluesSide(
	__global real* eigenvaluesBuffer,
	const __global real* stateBuffer,
	const __global real* potentialBuffer,
	int side);

void calcEigenvaluesSide(
	__global real* eigenvaluesBuffer,
	const __global real* stateBuffer,
	const __global real* potentialBuffer,
	int side)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);
	int indexPrev = index - stepsize[side];
	int interfaceIndex = side + DIM * index;

	real4 normal = (real4)(0.f, 0.f, 0.f, 0.f);
	normal[side] = 1;

	const __global real* stateL = stateBuffer + NUM_STATES * indexPrev;
	const __global real* stateR = stateBuffer + NUM_STATES * index;

	__global real* eigenvalues = eigenvaluesBuffer + NUM_STATES * interfaceIndex;

	//the left and right primitives are recalculated in calcEigenvalues and in calcFlux
	//if they could be stored somewhere, that might speed things up, but would take up a bit more memory

	real densityL = stateL[STATE_DENSITY];
	real invDensityL = 1.f / densityL;
	real4 velocityL = VELOCITY(stateL);
	real velocityNL = dot(velocityL, normal);
	real velocitySqL = dot(velocityL, velocityL);
	real energyTotalL = stateL[STATE_ENERGY_TOTAL] * invDensityL;
	real energyKineticL = .5f * velocitySqL;
	real energyPotentialL = potentialBuffer[indexPrev];
	real energyInternalL = energyTotalL - energyKineticL - energyPotentialL;
	real pressureL = (gamma - 1.f) * densityL * energyInternalL;
	real enthalpyTotalL = energyTotalL + pressureL * invDensityL;
	real speedOfSoundL = sqrt((gamma - 1.f) * (enthalpyTotalL - .5f * velocitySqL));
	real roeWeightL = sqrt(densityL);

	real densityR = stateR[STATE_DENSITY];
	real invDensityR = 1.f / densityR;
	real4 velocityR = VELOCITY(stateR);
	real velocityNR = dot(velocityR, normal);
	real velocitySqR = dot(velocityR, velocityR);
	real energyTotalR = stateR[STATE_ENERGY_TOTAL] * invDensityR;
	real energyKineticR = .5f * velocitySqR;
	real energyPotentialR = potentialBuffer[index];
	real energyInternalR = energyTotalR - energyKineticR - energyPotentialR;
	real pressureR = (gamma - 1.f) * densityR * energyInternalR;
	real enthalpyTotalR = energyTotalR + pressureR * invDensityR;
	real speedOfSoundR = sqrt((gamma - 1.f) * (enthalpyTotalR - .5f * velocitySqR));
	real roeWeightR = sqrt(densityR);
	
	real roeWeightNormalization = 1.f / (roeWeightL + roeWeightR);
	real4 velocity = (roeWeightL * velocityL + roeWeightR * velocityR) * roeWeightNormalization;
	real enthalpyTotal = (roeWeightL * enthalpyTotalL + roeWeightR * enthalpyTotalR) * roeWeightNormalization;
	real energyPotential = (roeWeightL * energyPotentialL + roeWeightR * energyPotentialR) * roeWeightNormalization; 
	
	real velocitySq = dot(velocity, velocity);
	real speedOfSound = sqrt((gamma - 1.f) * (enthalpyTotal - .5f * velocitySq - energyPotential));
	real velocityN = dot(velocity, normal);

	//eigenvalues

#if 0	//Roe
	eigenvalues[0] = velocityN - speedOfSound;
	eigenvalues[1] = velocityN;
#if DIM > 1
	eigenvalues[2] = velocityN;
#endif
#if DIM > 2
	eigenvalues[3] = velocityN;
#endif
	eigenvalues[DIM+1] = velocityN + speedOfSound;
#endif

#if 1	//using HLL wavespeed calc

	real eigenvaluesMinL = velocityNL - speedOfSoundL;
	real eigenvaluesMaxR = velocityNR + speedOfSoundR;
	real eigenvaluesMin = velocity.x - speedOfSound;
	real eigenvaluesMax = velocity.x + speedOfSound;
	real sl = min(eigenvaluesMinL, eigenvaluesMin);
	real sr = max(eigenvaluesMaxR, eigenvaluesMax);

	eigenvalues[0] = sl;
	eigenvalues[1] = velocityN;
#if DIM > 1
	eigenvalues[2] = velocityN;
#if DIM > 2
	eigenvalues[3] = velocityN;
#endif
#endif
	eigenvalues[DIM+1] = sr;

#endif
}

__kernel void calcEigenvalues(
	__global real* eigenvaluesBuffer,
	const __global real* stateBuffer,
	const __global real* potentialBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 1
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) return;
	calcEigenvaluesSide(eigenvaluesBuffer, stateBuffer, potentialBuffer, 0);
#if DIM > 1
	calcEigenvaluesSide(eigenvaluesBuffer, stateBuffer, potentialBuffer, 1);
#endif
#if DIM > 2
	calcEigenvaluesSide(eigenvaluesBuffer, stateBuffer, potentialBuffer, 2);
#endif
}

//do we want to use interface wavespeeds to calculate cfl?
// esp when the flux values are computed from cell wavespeeds
__kernel void calcCFL(
	__global real* cflBuffer,
	const __global real* eigenvaluesBuffer,
	real cfl)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);
	if (i.x < 2 || i.x >= SIZE_X - 1 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) {
		cflBuffer[index] = INFINITY;
		return;
	}

	real result = INFINITY;
	for (int side = 0; side < DIM; ++side) {
		int indexNext = index + stepsize[side];
		
		const __global real* eigenvaluesL = eigenvaluesBuffer + NUM_STATES * (side + DIM * index);
		const __global real* eigenvaluesR = eigenvaluesBuffer + NUM_STATES * (side + DIM * indexNext);

		real minLambda = 0.f;
		real maxLambda = 0.f;
		for (int i = 0; i < NUM_STATES; ++i) {	
			maxLambda = max(maxLambda, eigenvaluesL[i]);
			minLambda = min(minLambda, eigenvaluesR[i]);
		}

		real dum = dx[side] / (maxLambda - minLambda);
		result = min(result, dum);
	}
		
	cflBuffer[index] = cfl * result;
}

void calcFluxSide(
	__global real* fluxBuffer,
	const __global real* stateBuffer,
	const __global real* potentialBuffer,
	real dt_dx,
	int side);

void calcFluxSide(
	__global real* fluxBuffer,
	const __global real* stateBuffer,
	const __global real* potentialBuffer,
	real dt_dx,
	int side)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);
	int indexPrev = index - stepsize[side];
	int interfaceIndex = side + DIM * index;

	const __global real* srcStateL = stateBuffer + NUM_STATES * indexPrev;
	const __global real* srcStateR = stateBuffer + NUM_STATES * index;

	real stateL[NUM_STATES];
	real stateR[NUM_STATES];

	// rotate into x axis
	for (int i = 0; i < NUM_STATES; ++i) {
		stateL[i] = srcStateL[i];
		stateR[i] = srcStateR[i];
	}
	{
		real tmp;
		
		tmp = stateL[STATE_MOMENTUM_X];
		stateL[STATE_MOMENTUM_X] = stateL[STATE_MOMENTUM_X+side];
		stateL[STATE_MOMENTUM_X+side] = tmp;
		
		tmp = stateR[STATE_MOMENTUM_X];
		stateR[STATE_MOMENTUM_X] = stateR[STATE_MOMENTUM_X+side];
		stateR[STATE_MOMENTUM_X+side] = tmp;
	}

	__global real* flux = fluxBuffer + NUM_STATES * interfaceIndex;

	real densityL = stateL[STATE_DENSITY];
	real invDensityL = 1.f / densityL;
	real4 velocityL = VELOCITY(stateL);
	real velocitySqL = dot(velocityL, velocityL);
	real energyTotalL = stateL[STATE_ENERGY_TOTAL] * invDensityL;
	real energyKineticL = .5f * velocitySqL;
	real energyPotentialL = potentialBuffer[indexPrev];
	real energyInternalL = energyTotalL - energyKineticL - energyPotentialL;
	real pressureL = (gamma - 1.f) * densityL * energyInternalL;
	real enthalpyTotalL = energyTotalL + pressureL * invDensityL;
	real speedOfSoundL = sqrt((gamma - 1.f) * (enthalpyTotalL - .5f * velocitySqL));
//	real roeWeightL = sqrt(densityL);

	real densityR = stateR[STATE_DENSITY];
	real invDensityR = 1.f / densityR;
	real4 velocityR = VELOCITY(stateR);
	real velocitySqR = dot(velocityR, velocityR);
	real energyTotalR = stateR[STATE_ENERGY_TOTAL] * invDensityR;
	real energyKineticR = .5f * velocitySqR;
	real energyPotentialR = potentialBuffer[index];
	real energyInternalR = energyTotalR - energyKineticR - energyPotentialR;
	real pressureR = (gamma - 1.f) * densityR * energyInternalR;
	real enthalpyTotalR = energyTotalR + pressureR * invDensityR;
	real speedOfSoundR = sqrt((gamma - 1.f) * (enthalpyTotalR - .5f * velocitySqR));
//	real roeWeightR = sqrt(densityR);

//	real roeWeightNormalization = 1.f / (roeWeightL + roeWeightR);
//	real4 velocity = (roeWeightL * velocityL + roeWeightR * velocityR) * roeWeightNormalization;
//	real velocitySq = dot(velocity, velocity);
//	real enthalpyTotal = (roeWeightL * enthalpyTotalL + roeWeightR * enthalpyTotalR) * roeWeightNormalization;
//	real energyPotential = (roeWeightL * energyPotentialL + roeWeightR * energyPotentialR) * roeWeightNormalization; 
//	real speedOfSound = sqrt((gamma - 1.f) * (enthalpyTotal - .5f * velocitySq - energyPotential));
	
	//flux

	real pressureStar = max(0.f, .5f * (pressureL + pressureR) - .5f * (velocityR.x - velocityL.x) * .5f * (densityL + densityR) * .5f * (speedOfSoundL + speedOfSoundR));		//Toro, 1991
	real qL = pressureStar <= pressureL ? 1.f : sqrt(1.f + (gamma + 1.f) / (2.f * gamma) * (pressureStar / pressureL - 1.f));
	real qR = pressureStar <= pressureR ? 1.f : sqrt(1.f + (gamma + 1.f) / (2.f * gamma) * (pressureStar / pressureR - 1.f));

	real sl = velocityL.x - speedOfSoundL * qL;
	real sr = velocityR.x + speedOfSoundR * qR;


	real fluxL[NUM_STATES];
	fluxL[0] = densityL * velocityL.x;
	fluxL[1] = densityL * velocityL.x * velocityL.x +  pressureL;
#if DIM > 1
	fluxL[2] = densityL * velocityL.y * velocityL.x;
#endif
#if DIM > 2
	fluxL[3] = densityL * velocityL.z * velocityL.x;
#endif
	fluxL[DIM+1] = densityL * enthalpyTotalL * velocityL.x;


	real fluxR[NUM_STATES];
	fluxR[0] = densityR * velocityR.x;
	fluxR[1] = densityR * velocityR.x * velocityR.x + pressureR;
#if DIM > 1
	fluxR[2] = densityR * velocityR.y * velocityR.x;
#endif
#if DIM > 2
	fluxR[3] = densityR * velocityR.z * velocityR.x;
#endif
	fluxR[DIM+1] = densityR * enthalpyTotalR * velocityR.x;	

//#define HLLC_METHOD		0
//#define HLLC_METHOD		1
#define HLLC_METHOD		2

	//HLLC-specific
	real sStar = (densityR * velocityR.x * (sr - velocityR.x) - densityL * velocityL.x * (sl - velocityL.x) + pressureL - pressureR) 
					/ (densityR * (sr - velocityR.x) - densityL * (sl - velocityL.x));
	if (0 <= sl) {
		for (int i = 0; i < NUM_STATES; ++i) {
			flux[i] = fluxL[i];
		}
	} else if (sl <= 0.f && 0.f <= sStar) {
#if HLLC_METHOD == 0

		real stateLStar[NUM_STATES];
		stateLStar[STATE_DENSITY] = densityL * (sl - velocityL.x) / (sl - sStar);
		stateLStar[STATE_MOMENTUM_X] = stateLStar[STATE_DENSITY] * sStar;
#if DIM > 1
		stateLStar[STATE_MOMENTUM_Y] = stateLStar[STATE_DENSITY] * velocityL.y;
#if DIM > 2
		stateLStar[STATE_MOMENTUM_Z] = stateLStar[STATE_DENSITY] * velocityL.z;
#endif
#endif
		stateLStar[STATE_ENERGY_TOTAL] = stateLStar[STATE_DENSITY] * (energyTotalL + (sStar - velocityL.x) * (sStar + pressureL / (densityL * (sl - velocityL.x))));
		for (int i = 0; i < NUM_STATES; ++i) {
			flux[i] = fluxL[i] + sl * (stateLStar[i] - stateL[i]);
		}

#elif HLLC_METHOD == 1
		
		flux[STATE_DENSITY] = (sStar * (sl * stateL[STATE_DENSITY] - fluxL[STATE_DENSITY])) / (sl - sStar);
		flux[STATE_MOMENTUM_X] = (sStar * (sl * stateL[STATE_MOMENTUM_X] - fluxL[STATE_MOMENTUM_X]) + sl * (pressureL + densityL * (sl - velocityL.x) * (sStar - velocityL.x))) / (sl - sStar);
#if DIM > 1
		flux[STATE_MOMENTUM_Y] = (sStar * (sl * stateL[STATE_MOMENTUM_Y] - fluxL[STATE_MOMENTUM_Y])) / (sl - sStar);
#if DIM > 2
		flux[STATE_MOMENTUM_Z] = (sStar * (sl * stateL[STATE_MOMENTUM_Z] - fluxL[STATE_MOMENTUM_Z])) / (sl - sStar);
#endif
#endif
		flux[STATE_ENERGY_TOTAL] = (sStar * (sl * stateL[STATE_ENERGY_TOTAL] - fluxL[STATE_ENERGY_TOTAL]) + sl * (pressureL + densityL * (sl - velocityL.x) * (sStar - velocityL.x)) * sStar) / (sl - sStar);

#elif HLLC_METHOD == 2
		
		real pressureLR = .5f * (pressureL + pressureR + densityL * (sl - velocityL.x) * (sStar - velocityL.x) + densityR * (sr - velocityR.x) * (sStar - velocityR.x));
		flux[STATE_DENSITY] = sStar * (sl * stateL[STATE_DENSITY] - fluxL[STATE_DENSITY]) / (sl - sStar);
		flux[STATE_MOMENTUM_X] = (sStar * (sl * stateL[STATE_MOMENTUM_X] - fluxL[STATE_MOMENTUM_X]) + sl * pressureLR) / (sl - sStar);
#if DIM > 1
		flux[STATE_MOMENTUM_Y] = sStar * (sl * stateL[STATE_MOMENTUM_Y] - fluxL[STATE_MOMENTUM_Y]) / (sl - sStar);
#if DIM > 2
		flux[STATE_MOMENTUM_Z] = sStar * (sl * stateL[STATE_MOMENTUM_Z] - fluxL[STATE_MOMENTUM_Z]) / (sl - sStar);
#endif
#endif
		flux[STATE_ENERGY_TOTAL] = (sStar * (sl * stateL[STATE_ENERGY_TOTAL] - fluxL[STATE_ENERGY_TOTAL]) + sl * pressureLR * sStar) / (sl - sStar);

#endif	// HLLC_METHOD
	} else if (sStar <= 0.f && 0.f <= sr) {
#if HLLC_METHOD == 0
		
		real stateRStar[NUM_STATES];
		stateRStar[STATE_DENSITY] = densityR * (sr - velocityR.x) / (sr - sStar);
		stateRStar[STATE_MOMENTUM_X] = stateRStar[STATE_DENSITY] * sStar;
#if DIM > 1
		stateRStar[STATE_MOMENTUM_Y] = stateRStar[STATE_DENSITY] * velocityR.y;
#if DIM > 2
		stateRStar[STATE_MOMENTUM_Z] = stateRStar[STATE_DENSITY] * velocityR.z;
#endif
#endif
		stateRStar[STATE_ENERGY_TOTAL] = stateRStar[STATE_DENSITY] * (energyTotalR + (sStar - velocityR.x) * (sStar + pressureR / (densityR * (sr - velocityR.x))));
		for (int i = 0; i < NUM_STATES; ++i) {
			flux[i] = fluxR[i] + sr * (stateRStar[i] - stateR[i]);
		}

#elif HLLC_METHOD == 1
		
		flux[STATE_DENSITY] = (sStar * (sr * stateR[STATE_DENSITY] - fluxR[STATE_DENSITY])) / (sr - sStar);
		flux[STATE_MOMENTUM_X] = (sStar * (sr * stateR[STATE_MOMENTUM_X] - fluxR[STATE_MOMENTUM_X]) + sr * (pressureR + densityR * (sr - velocityR.x) * (sStar - velocityR.x))) / (sr - sStar);
#if DIM > 1
		flux[STATE_MOMENTUM_Y] = (sStar * (sr * stateR[STATE_MOMENTUM_Y] - fluxR[STATE_MOMENTUM_Y])) / (sr - sStar);
#if DIM > 2
		flux[STATE_MOMENTUM_Z] = (sStar * (sr * stateR[STATE_MOMENTUM_Z] - fluxR[STATE_MOMENTUM_Z])) / (sr - sStar);
#endif
#endif
		flux[STATE_ENERGY_TOTAL] = (sStar * (sr * stateR[STATE_ENERGY_TOTAL] - fluxR[STATE_ENERGY_TOTAL]) + sr * (pressureR + densityR * (sr - velocityR.x) * (sStar - velocityR.x)) * sStar) / (sr - sStar);

#elif HLLC_METHOD == 2
		
		real pressureLR = .5f * (pressureL + pressureR + densityL * (sl - velocityL.x) * (sStar - velocityL.x) + densityR * (sr - velocityR.x) * (sStar - velocityR.x));
		flux[STATE_DENSITY] = sStar * (sr * stateR[STATE_DENSITY] - fluxR[STATE_DENSITY]) / (sr - sStar);
		flux[STATE_MOMENTUM_X] = (sStar * (sr * stateR[STATE_MOMENTUM_X] - fluxR[STATE_MOMENTUM_X]) + sr * pressureLR) / (sr - sStar);
#if DIM > 1
		flux[STATE_MOMENTUM_Y] = sStar * (sr * stateR[STATE_MOMENTUM_Y] - fluxR[STATE_MOMENTUM_Y]) / (sr - sStar);
#if DIM > 2
		flux[STATE_MOMENTUM_Z] = sStar * (sr * stateR[STATE_MOMENTUM_Z] - fluxR[STATE_MOMENTUM_Z]) / (sr - sStar);
#endif
#endif
		flux[STATE_ENERGY_TOTAL] = (sStar * (sr * stateR[STATE_ENERGY_TOTAL] - fluxR[STATE_ENERGY_TOTAL]) + sr * pressureLR * sStar) / (sr - sStar);

#endif	// HLLC_METHOD
	} else if (sr <= 0.f) {
		for (int i = 0; i < NUM_STATES; ++i) {
			flux[i] = fluxR[i];
		}
	}


/*
slope limiter?

theta = sign of eigenvalues

fhalf = 1/2 (fR + fL) - 1/2 (theta + phi (epsilon - theta)) (fR - fL)

donor cell when phi = 0:

fhalf = 1/2 (fR + fL) - 1/2 theta (fR - fL)
... for theta = 1: 	fhalf = 1/2 fR + 1/2 fL - 1/2 fR + 1/2 fL = fL
... for theta = -1:	fhalf = 1/2 fR + 1/2 fL + 1/2 fR - 1/2 fL = fR

... for phi = slope of rTile
			= for theta = 1:	delta q(i-1) / delta q(i)
			= for theta = -1:	delta q(i+1) / delta q(i)

so what do we use to consider delta q?  the states themselves, or any sort of transformation (as Roe does)?
how about (by Hydrodynamics ii) delta q = delta f / lambda
so what is delta f?  
Hydrodynamics ii stops at mentioning the deconstruction of delta q into delta q- and delta q+
 and its association with lambda+ and lambda-
 which are the eigenvalue min and max used in the flux calculation.
 is this the slope that should be used with the slope limiter?
or can we use delta q- and delta q+ for the lhs and rhs of the delta q slope, choosing one or the other based on the velocity sign 
*/
#if 0
	for (int i = 0; i < NUM_STATES; ++i) {
		real eigenvalue = eigenvalues[i];
		real deltaFlux = fluxR[i] - fluxL[i];
		real deltaQ = stateR[i] - stateL[i];
		real rTilde = deltaFlux / deltaQ;
		real theta;
		if (eigenvalue >= 0.f) {
			theta = 1.f;
			//rTilde = (stateMid - stateL[i]) / deltaQ;
		} else {
			theta = -1.f;
			//rTilde = (stateR[i] - stateMid) / deltaQ;
		}
		real phi = slopeLimiter(rTilde);
		real epsilon = eigenvalue * dt_dx;
		flux[i] -= .5f * deltaFlux * (theta + phi * (epsilon - theta) / (real)DIM);
	}
#endif

	//rotate back to side
	{
		real tmp = flux[STATE_MOMENTUM_X];
		flux[STATE_MOMENTUM_X] = flux[STATE_MOMENTUM_X + side];
		flux[STATE_MOMENTUM_X + side] = tmp;
	}
}

__kernel void calcFlux(
	__global real* fluxBuffer,
	const __global real* stateBuffer,
	const __global real* potentialBuffer,
	const __global real* dtBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 1
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) return;
	
	real dt = dtBuffer[0];
	
	calcFluxSide(fluxBuffer, stateBuffer, potentialBuffer, dt/DX, 0);
#if DIM > 1
	calcFluxSide(fluxBuffer, stateBuffer, potentialBuffer, dt/DY, 1);
#endif
#if DIM > 2
	calcFluxSide(fluxBuffer, stateBuffer, potentialBuffer, dt/DZ, 2);
#endif
}

__kernel void calcFluxDeriv(
	__global real* derivBuffer,
	const __global real* fluxBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 1 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) return;
	int index = INDEXV(i);

	__global real* deriv = derivBuffer + NUM_STATES * index;

	for (int side = 0; side < DIM; ++side) {
		int indexNext = index + stepsize[side];
		const __global real* fluxL = fluxBuffer + NUM_STATES * (side + DIM * index);
		const __global real* fluxR = fluxBuffer + NUM_STATES * (side + DIM * indexNext);
		for (int j = 0; j < NUM_STATES; ++j) {
			real deltaFlux = fluxR[j] - fluxL[j];
			deriv[j] -= deltaFlux / dx[side];
		}
	}
}

