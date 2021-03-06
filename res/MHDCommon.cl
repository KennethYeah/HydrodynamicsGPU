#include "HydroGPU/MHD.h"

#define gamma idealGas_heatCapacityRatio	//laziness

Primitives_t calcPrimitivesFromState(real8 state, real potentialEnergy);
Primitives_t calcPrimitivesFromState(real8 state, real potentialEnergy) {
	Primitives_t prims;
	prims.density = state[STATE_DENSITY];
	prims.velocity = VELOCITY(state);
	prims.magneticField = (real4)(state[STATE_MAGNETIC_FIELD_X], state[STATE_MAGNETIC_FIELD_Y], state[STATE_MAGNETIC_FIELD_Z], 0.);
	real magneticEnergyDensity = .5 * dot(prims.magneticField, prims.magneticField) / mhd_vacuumPermeability;
	real totalPlasmaEnergyDensity = state[STATE_ENERGY_TOTAL];
	real totalHydroEnergyDensity = totalPlasmaEnergyDensity - magneticEnergyDensity;
	real kineticEnergyDensity = .5 * prims.density * dot(prims.velocity, prims.velocity);
	real potentialEnergyDensity = prims.density * potentialEnergy; 
	real internalEnergyDensity = totalHydroEnergyDensity - kineticEnergyDensity - potentialEnergyDensity;
internalEnergyDensity = max(0., internalEnergyDensity);	//magnetic energy is exceeding total energy ...
	prims.pressure = (gamma - 1.) * internalEnergyDensity;
	prims.pressureTotal = prims.pressure + magneticEnergyDensity;
	//not used by wavespeed, only by flux calc
	prims.enthalpyTotal = (totalHydroEnergyDensity + prims.pressure) / prims.density;
	return prims;
}

Wavespeed_t calcWavespeedFromPrimitives(Primitives_t prims);
Wavespeed_t calcWavespeedFromPrimitives(Primitives_t prims) {
	Wavespeed_t speed;
	real speedOfSoundSq = gamma * prims.pressure / prims.density;
	//real speedOfSound = sqrt(speedOfSoundSq);
	real sqrtDensity = sqrt(prims.density);
	speed.Alfven = fabs(prims.magneticField.x) / (sqrtDensity * mhd_sqrt_vacuumPermeability);
	real AlfvenSpeedSq = speed.Alfven * speed.Alfven;
	real magneticFieldSq = dot(prims.magneticField, prims.magneticField);
	real starSpeedSq = .5 * (speedOfSoundSq + magneticFieldSq / (prims.density * mhd_vacuumPermeability));
	real discr = starSpeedSq * starSpeedSq - speedOfSoundSq * AlfvenSpeedSq;
	real discrSqrt = sqrt(discr);
	real fastSpeedSq = starSpeedSq + discrSqrt;
	speed.fast = sqrt(fastSpeedSq);
	real slowSpeedSq = starSpeedSq - discrSqrt;
	speed.slow = sqrt(slowSpeedSq);
	return speed;
}

real8 rotateStateToX(const __global real* srcState, int side);
real8 rotateStateToX(const __global real* srcState, int side) {
#if NUM_STATES != 8
#error expected 8 states
#endif
	real8 state = *(const __global real8*)srcState;
	
	// rotate into x axis
	real tmp;
	
	tmp = state[STATE_MOMENTUM_X];
	state[STATE_MOMENTUM_X] = state[STATE_MOMENTUM_X+side];
	state[STATE_MOMENTUM_X+side] = tmp;
	
	tmp = state[STATE_MAGNETIC_FIELD_X];
	state[STATE_MAGNETIC_FIELD_X] = state[STATE_MAGNETIC_FIELD_X+side];
	state[STATE_MAGNETIC_FIELD_X+side] = tmp;
	
	return state;
}
