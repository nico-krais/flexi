!=================================================================================================================================
! Copyright (c) 2016  Prof. Claus-Dieter Munz 
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"

!===================================================================================================================================
!> Contains routines to read in the state (with or without gradients) - if we want the gradients, DGTimeDerivative_weakForm is
!> called once.
!===================================================================================================================================
MODULE MOD_Posti_ReadState
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------

INTERFACE ReadState
  MODULE PROCEDURE ReadState
END INTERFACE

PUBLIC:: ReadState

CONTAINS

!===================================================================================================================================
!> This routine will read in the current state from the statefile. Will call one of two routines: ReadStateWithoutGradients if no
!> gradients have to be visualized or calculated and so no DG operator call is necessary, or ReadStateAndGradients if gradients
!> are needed and we need to calculate the DG operator once.
!> If the DG operator has to be called, we need some parameters. Either a seperate parameter file is passed,  then this one will 
!> be used, or we try to extract the parameter file from the userblock.
!> If both fails and we need to compute the DG operator, the program will abort.
!> If the DG operator should not be called and no parameter file (seperate or from userblock) can be found,
!> we specify PP_N from the state file as our polynomial degree (later needed by InitInterpolation).
!===================================================================================================================================
SUBROUTINE ReadState(prmfile,statefile)
USE MOD_Globals
USE MOD_PreProc
USE MOD_Visu_Vars   ,ONLY:withDGOperator
USE MOD_ReadInTools ,ONLY:ExtractParameterFile
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES 
CHARACTER(LEN=255),INTENT(INOUT) :: prmfile      !< FLEXI parameter file, used if DG operator is called
CHARACTER(LEN=255),INTENT(IN)    :: statefile    !< HDF5 state file
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: userblockFound
!===================================================================================================================================
userblockFound = .TRUE. ! Set to true to later test for existing parameters either form userblock or from seperate file
IF (LEN_TRIM(prmfile).EQ.0) THEN ! No seperate parameter file has been given
  ! Try to extract parameter file 
  prmfile = ".flexi.ini"
  CALL ExtractParameterFile(statefile,prmfile,userblockFound)
  ! Only abort if we need some parameters to call the DG operator
  IF (.NOT.userblockFound.AND.withDGOperator) THEN
    CALL CollectiveStop(__STAMP__, "No userblock found in state file '"//TRIM(statefile)//"' and no parameter file specified.")
  END IF
END IF
SWRITE(*,*) "[ALL] get solution. withDGOperator = ", withDGOperator
IF (withDGOperator) THEN
  CALL ReadStateAndGradients(prmfile,statefile)
ELSE
  ! If no parameters have been specified, use PP_N to later initialize the interpolation routines.
  IF (.NOT.userblockFound) THEN
    CALL ReadStateWithoutGradients(prmfile,statefile,PP_N)
  ELSE
    CALL ReadStateWithoutGradients(prmfile,statefile)
  END IF
END IF
END SUBROUTINE ReadState

!===================================================================================================================================
!> Read a state file via Restart routine and preforms one DGTimeDerivative_weakForm.
!> This fill at least 'U', 'UPrim', and the gradients 'gradUx/y/z'.
!===================================================================================================================================
SUBROUTINE ReadStateAndGradients(prmfile,statefile)
! MODULES                                                                   
USE MOD_Globals
USE MOD_PreProc
USE MOD_Visu_Vars
USE MOD_MPI           ,ONLY: DefineParametersMPI
#if USE_MPI
USE MOD_MPI           ,ONLY: InitMPIvars,FinalizeMPI
#endif
USE MOD_IO_HDF5       ,ONLY: DefineParametersIO_HDF5,InitIOHDF5
USE MOD_Interpolation ,ONLY: DefineParametersInterpolation,InitInterpolation,FinalizeInterpolation
USE MOD_Restart       ,ONLY: DefineParametersRestart,InitRestart,Restart,FinalizeRestart
USE MOD_Mesh          ,ONLY: DefineParametersMesh,InitMesh,FinalizeMesh
USE MOD_Indicator     ,ONLY: DefineParametersIndicator,InitIndicator,FinalizeIndicator
#if FV_ENABLED
USE MOD_FV            ,ONLY: DefineParametersFV,InitFV,FinalizeFV
USE MOD_FV_Basis      ,ONLY: InitFV_Basis,FinalizeFV_Basis
#endif
USE MOD_DG            ,ONLY: InitDG,DGTimeDerivative_weakForm,FinalizeDG
USE MOD_Mortar        ,ONLY: InitMortar,FinalizeMortar
USE MOD_EOS           ,ONLY: DefineParametersEos
USE MOD_Equation      ,ONLY: DefineParametersEquation,InitEquation,FinalizeEquation
USE MOD_Exactfunc     ,ONLY: DefineParametersExactFunc
#if PARABOLIC
USE MOD_Lifting       ,ONLY: DefineParametersLifting,InitLifting,FinalizeLifting
#endif
USE MOD_Filter,         ONLY:DefineParametersFilter,InitFilter,FinalizeFilter
USE MOD_Overintegration,ONLY:DefineParametersOverintegration,InitOverintegration,FinalizeOverintegration
USE MOD_ReadInTools   ,ONLY: prms
USE MOD_ReadInTools   ,ONLY: FinalizeParameters
USE MOD_Restart_Vars  ,ONLY: RestartTime
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES 
CHARACTER(LEN=255),INTENT(IN):: prmfile       !< FLEXI parameter file, used if DG operator is called
CHARACTER(LEN=255),INTENT(IN):: statefile     !< HDF5 state file
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
CALL FinalizeInterpolation()
#if FV_ENABLED
CALL FinalizeFV_Basis()
CALL FinalizeFV()
#endif
CALL FinalizeMortar()
CALL FinalizeRestart()
#if USE_MPI
IF (changedMeshFile.OR.changedWithDGOperator) THEN
  CALL FinalizeMPI()
END IF
#endif
CALL FinalizeIndicator()
CALL FinalizeEquation()
CALL FinalizeDG()
CALL FinalizeOverintegration()
CALL FinalizeFilter()
#if PARABOLIC
CALL FinalizeLifting()
#endif

! read options from parameter file
CALL FinalizeParameters()
CALL DefineParametersMPI()
CALL DefineParametersIO_HDF5()
CALL DefineParametersInterpolation()
CALL DefineParametersRestart()
CALL DefineParametersMesh()
CALL DefineParametersFilter()
CALL DefineParametersOverintegration()
CALL DefineParametersIndicator()
#if FV_ENABLED
CALL DefineParametersFV()
#endif
CALL DefineParametersEos()
CALL DefineParametersEquation()
CALL DefineParametersExactFunc()
#if PARABOLIC
CALL DefineParametersLifting()
#endif
CALL prms%read_options(prmfile)

! Initialization of I/O routines
CALL InitIOHDF5()

CALL InitInterpolation()
#if FV_ENABLED
CALL InitFV_Basis()
#endif
CALL InitMortar()
CALL InitRestart(statefile)

! TODO: what todo with vars that are set in InitOutput, that normally is executed here.

IF (changedMeshFile.OR.changedWithDGOperator) THEN
  CALL FinalizeMesh()
  CALL InitMesh(meshMode=2,MeshFile_IN=MeshFile)
END IF

CALL InitFilter()
CALL InitOverintegration()
CALL InitIndicator()
#if USE_MPI
IF (changedMeshFile.OR.changedWithDGOperator) THEN
  CALL InitMPIvars()
END IF
#endif
CALL InitEquation()

CALL InitDG()
#if FV_ENABLED
CALL InitFV()
#endif
#if PARABOLIC
CALL InitLifting()
#endif /*PARABOLIC*/
CALL Restart(doFlushFiles=.FALSE.)
SWRITE(*,*) "Call DGTimeDerivative_weakForm ... "
CALL DGTimeDerivative_weakForm(RestartTime)
SWRITE(*,*) "  DONE"

CALL FinalizeParameters()
END SUBROUTINE ReadStateAndGradients


!===================================================================================================================================
!> Read 'U' directly from a state file.
!===================================================================================================================================
SUBROUTINE ReadStateWithoutGradients(prmfile,statefile,Nin)
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Visu_Vars
USE MOD_MPI,                 ONLY: DefineParametersMPI
#if USE_MPI
USE MOD_MPI,                 ONLY: FinalizeMPI
#endif
USE MOD_IO_HDF5,             ONLY: DefineParametersIO_HDF5,InitIOHDF5
USE MOD_Mesh                ,ONLY: DefineParametersMesh,InitMesh,FinalizeMesh
USE MOD_ReadInTools         ,ONLY: prms
USE MOD_ReadInTools         ,ONLY: FinalizeParameters
USE MOD_Mesh_Vars           ,ONLY: nElems,offsetElem
USE MOD_HDF5_Input,          ONLY: OpenDataFile,ReadArray,CloseDataFile
USE MOD_DG_Vars             ,ONLY: U
USE MOD_EOS                 ,ONLY: DefineParametersEos,InitEOS
USE MOD_Interpolation       ,ONLY: DefineParametersInterpolation,InitInterpolation,FinalizeInterpolation
#if FV_ENABLED
USE MOD_FV_Basis            ,ONLY: InitFV_Basis,FinalizeFV_Basis
#endif
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES 
CHARACTER(LEN=255),INTENT(IN):: prmfile       !< FLEXI parameter file, used if DG operator is called
CHARACTER(LEN=255),INTENT(IN):: statefile     !< HDF5 state file
INTEGER,INTENT(IN),OPTIONAL  :: Nin           !< Polynomial degree used in InitInterpolation (OPTIONAL)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: meshMode_loc
LOGICAL           :: changedMeshMode
!===================================================================================================================================
CALL FinalizeInterpolation()

! Some features require normal vectors or metrics
meshMode_loc = 0 ! Minimal mesh init
IF (doSurfVisu)  meshMode_loc = MAX(meshMode_loc,2)
IF (hasFV_Elems) meshMode_loc = MAX(meshMode_loc,2)


#if FV_ENABLED
! For FV and higher mesh modes the FV basis is needed
IF (meshMode_loc.EQ.2) CALL FinalizeFV_Basis()
#endif

! check if the mesh mode has changed from the last time
changedMeshMode = (meshMode_loc.NE.meshMode_old)


#if USE_MPI
IF ((changedMeshFile).OR.(changedMeshMode)) THEN
  CALL FinalizeMPI()
END IF
#endif

! read options from parameter file
CALL FinalizeParameters()
CALL DefineParametersMPI()
CALL DefineParametersIO_HDF5()
CALL DefineParametersInterpolation()
CALL DefineParametersMesh()
CALL DefineParametersEOS()
CALL prms%read_options(prmfile)

! Initialization of I/O routines
CALL InitIOHDF5()
CALL InitEOS()

IF (PRESENT(NIn)) THEN
  CALL InitInterpolation(Nin)
ELSE
  CALL InitInterpolation()
END IF

#if FV_ENABLED
! We need to call the FV basis init to allocate some arrays needed in mesh init
IF (meshMode_loc.EQ.2) CALL InitFV_Basis()
#endif

! Call mesh init if the mesh file changed or we need a different mesh mode
IF ((changedMeshFile).OR.(changedMeshMode)) THEN
  CALL FinalizeMesh()
  CALL InitMesh(meshMode=meshMode_loc,MeshFile_IN=MeshFile)
END IF

! save old mesh mode for future comparison
meshMode_old = meshMode_loc

SDEALLOCATE(U)
ALLOCATE(U(1:nVar_State,0:PP_N,0:PP_N,0:PP_N,nElems))
CALL OpenDataFile(statefile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
CALL ReadArray('DG_Solution',5,(/nVar_State,PP_N+1,PP_N+1,PP_N+1,nElems/),offsetElem,5,RealArray=U)  
CALL CloseDataFile()

CALL FinalizeParameters()
END SUBROUTINE ReadStateWithoutGradients

END MODULE MOD_Posti_ReadState
