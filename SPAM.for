C=======================================================================
C  COPYRIGHT 1998-2010 The University of Georgia, Griffin, Georgia
C                      University of Florida, Gainesville, Florida
C                      Iowa State University, Ames, Iowa
C                      International Center for Soil Fertility and 
C                       Agricultural Development, Muscle Shoals, Alabama
C                      University of Guelph, Guelph, Ontario
C  ALL RIGHTS RESERVED
C=======================================================================
C=======================================================================
C  SPAM, Subroutine
C  Calculates soil-plant-atmosphere interface energy balance components.
C-----------------------------------------------------------------------
C  REVISION       HISTORY
C  11/09/2001 WMB/CHP Split WATBAL into WATBAL and SPAM.
C  02/06/2003 KJB/CHP Added KEP, EORATIO inputs from plant routines.
C  06/19/2003 CHP Added KTRANS - used instead of KEP in TRANS.
C  04/01/2004 CHP/US Added Penman - Meyer routine for potential ET
!  10/24/2005 CHP Put weather variables in constructed variable. 
!  07/24/2006 CHP Use MSALB instead of SALB (includes mulch and soil 
!                 water effects on albedo)
!  08/25/2006 CHP Add SALUS soil evaporation routine, triggered by new
!                 FILEX parameter MESEV
!  12/09/2008 CHP Remove METMP
!  10/20/2009 CHP Soil water stress factors computed in SPAM to accomodate
!                   2D, variable time step model.
C-----------------------------------------------------------------------
C  Called by: Main
C  Calls:     XTRACT, OPSPAM    (File SPSUBS.FOR)
C             PET     (File PET.FOR)
C             PSE     (File PET.FOR)
C             ROOTWU  (File ROOTWU.FOR)
C             SOILEV  (File SOILEV.FOR)
C             TRANS   (File TRANS.FOR)
C=======================================================================

      SUBROUTINE SPAM(CONTROL, ISWITCH,
     &    CANHT, EORATIO, KSEVAP, KTRANS, MULCH,          !Input
     &    RLV, SOILPROP, SW, SWDELTS, WEATHER,            !Input
     &    WINF, XHLAI, XLAI,                              !Input
     &    FLOODWAT, SWDELTU,                              !I/O
     &    EO, EOP, EOS, EP, ES, SRFTEMP, ST, SWDELTX,     !Output
     &    SWFAC, TRWU, TRWUP, TURFAC, UPFLOW)             !Output

!-----------------------------------------------------------------------
      USE ModuleDefs 
      USE ModuleData
      USE FloodModule

      IMPLICIT NONE
      SAVE

      CHARACTER*1  IDETW, ISWWAT
      CHARACTER*1  MEEVP, MEINF, MEPHO, MESEV   !  , METMP
      CHARACTER*2  CROP
      CHARACTER*6, PARAMETER :: ERRKEY = "SPAM  "
!      CHARACTER*78 MSG(2)

      INTEGER DYNAMIC, L, NLAYR

      REAL CANHT, CO2, SRAD, TAVG, 
     &    TMAX, TMIN, WINDSP, XHLAI, XLAI
      REAL CEF, CEM, CEO, CEP, CES, CET, EF, EM, EO, EP, ES, ET,
     &    TRWU, TRWUP, U
      REAL EOS, EOP, WINF, MSALB, ET_ALB
      REAL XLAT, TAV, TAMP, SRFTEMP
      REAL EORATIO, KSEVAP, KTRANS
      REAL RWUEP1, SWFAC, TURFAC

      REAL DLAYR(NL), DUL(NL), LL(NL), RLV(NL), RWU(NL),  
     &    SAT(NL), ST(NL), SW(NL), SW_AVAIL(NL), !SWAD(NL), 
     &    SWDELTS(NL), SWDELTU(NL), SWDELTX(NL), UPFLOW(NL)
      REAL ES_LYR(NL)

!     Flood management variables:
      REAL FLOOD

!-----------------------------------------------------------------------
!     Define constructed variable types based on definitions in
!     ModuleDefs.for.
      TYPE (ControlType) CONTROL
      TYPE (SoilType) SOILPROP
      TYPE (SwitchType) ISWITCH
      TYPE (FloodWatType) FLOODWAT
      TYPE (MulchType)   MULCH
      TYPE (WeatherType)  WEATHER

!     Transfer values from constructed data types into local variables.
      CROP    = CONTROL % CROP
      DYNAMIC = CONTROL % DYNAMIC

      DLAYR  = SOILPROP % DLAYR
      DUL    = SOILPROP % DUL
      LL     = SOILPROP % LL
      MSALB  = SOILPROP % MSALB
      NLAYR  = SOILPROP % NLAYR
      SAT    = SOILPROP % SAT
      U      = SOILPROP % U

      ISWWAT = ISWITCH % ISWWAT
      IDETW  = ISWITCH % IDETW
      MEEVP  = ISWITCH % MEEVP
      MEINF  = ISWITCH % MEINF
      MEPHO  = ISWITCH % MEPHO
!     METMP  = ISWITCH % METMP
      MESEV  = ISWITCH % MESEV

      FLOOD  = FLOODWAT % FLOOD

      CO2    = WEATHER % CO2
      SRAD   = WEATHER % SRAD  
      TAMP   = WEATHER % TAMP  
      TAV    = WEATHER % TAV   
      TAVG   = WEATHER % TAVG  
      TMAX   = WEATHER % TMAX  
      TMIN   = WEATHER % TMIN  
      WINDSP = WEATHER % WINDSP
      XLAT   = WEATHER % XLAT  

!***********************************************************************
!***********************************************************************
!     Run Initialization - Called once per simulation
!***********************************************************************
      IF (DYNAMIC .EQ. RUNINIT) THEN
!-----------------------------------------------------------------------
      IF (MEPHO .EQ. 'L' .OR. MEEVP .EQ. 'Z') THEN
        CALL ETPHOT(CONTROL, ISWITCH,
     &    RLV, SOILPROP, ST, SW, WEATHER, XHLAI,          !Input
     &    EOP, EP, ES, RWU, TRWUP)                        !Output
      ENDIF

!***********************************************************************
!***********************************************************************
!     Seasonal initialization - run once per season
!***********************************************************************
      ELSEIF (DYNAMIC .EQ. SEASINIT) THEN
!-----------------------------------------------------------------------
      EF   = 0.0; CEF = 0.0
      EM   = 0.0; CEM = 0.0
      EO   = 0.0; CEO  = 0.0
      EP   = 0.0; CEP  = 0.0
      ES   = 0.0; CES  = 0.0
      ET   = 0.0; CET  = 0.0
      ES_LYR = 0.0
      SWDELTX = 0.0
      TRWU = 0.0

!     Soil water stress variables
      SWFAC  = 1.0
      TURFAC = 1.0

      CALL GET('PLANT','RWUEP1',RWUEP1)

!     ---------------------------------------------------------
      CALL STEMP(CONTROL, ISWITCH,
     &    SOILPROP, SRAD, SW, TAVG, TMAX, XLAT, TAV, TAMP,!Input
     &    SRFTEMP, ST)                                    !Output

!     ---------------------------------------------------------
      IF (MEEVP .NE. 'Z') THEN
        SELECT CASE (CONTROL % MESIC)
        CASE ('H')
          CALL ROOTWU_HR(SEASINIT,  
     &      DLAYR, EOP, ES_LYR, LL, NLAYR, RLV,           !Input
     &      SAT, SW, WEATHER,                             !Input
     &      EP, RWU, SWDELTX, SWFAC, TRWU, TRWUP, TURFAC) !Output
        CASE DEFAULT
          CALL ROOTWU(SEASINIT,
     &    DLAYR, LL, NLAYR, RLV, SAT, SW,                 !Input
     &    RWU, TRWUP)                                     !Output
        END SELECT

!       Initialize soil evaporation variables
        SELECT CASE (MESEV)
!     ----------------------------
        CASE ('R')  !Original soil evaporation routine
          CALL SOILEV(SEASINIT,
     &      DLAYR, DUL, EOS, LL, SW, SW_AVAIL(1),         !Input
     &      U, WINF,                                      !Input
     &      ES)                                           !Output
!     ----------------------------
!        CASE ('S')  !SALUS soil evaporation routine
         !CALL ESR_SoilEvap(SEASINIT,
     &   ! EOS, Pond_EV, SOILPROP, SW, SW_AVAIL,           !Input
     &   ! ES, SWDELTU, SWAD, UPFLOW)                      !Output
!     ----------------------------
        END SELECT

!       Initialize plant transpiration variables
        CALL TRANS(DYNAMIC, 
     &    CO2, CROP, EO, ES, KTRANS, TAVG, WINDSP, XHLAI, !Input
     &    EOP)                                            !Output
      ENDIF

      CALL MULCH_EVAP(DYNAMIC, MULCH, EOS, EM)

!     ---------------------------------------------------------
      IF (CROP .NE. 'FA') THEN
        IF (MEPHO .EQ. 'L' .OR. MEEVP .EQ. 'Z') THEN
          CALL ETPHOT(CONTROL, ISWITCH,
     &    RLV, SOILPROP, ST, SW, WEATHER, XHLAI,          !Input
     &    EOP, EP, ES, RWU, TRWUP)                        !Output
        ENDIF
      ENDIF

!     Call OPSPAM to open and write headers to output file
      IF (IDETW .EQ. 'Y') THEN
        CALL OPSPAM(CONTROL, ISWITCH, FLOODWAT,
     &    CEF, CEM, CEO, CEP, CES, CET, EF, EM, 
     &    EO, EOP, EOS, EP, ES, ET, TMAX, TMIN, TRWUP, SRAD,
     &    ES_LYR, SOILPROP)
      ENDIF

!     Transfer data to storage routine
      CALL PUT('SPAM', 'CEF', CEF)
      CALL PUT('SPAM', 'CEM', CEM)
      CALL PUT('SPAM', 'CEO', CEO)
      CALL PUT('SPAM', 'CEP', CEP)
      CALL PUT('SPAM', 'CES', CES)
      CALL PUT('SPAM', 'CET', CET)
      CALL PUT('SPAM', 'EF',  EF)
      CALL PUT('SPAM', 'EM',  EM)
      CALL PUT('SPAM', 'EO',  EO)
      CALL PUT('SPAM', 'EP',  EP)
      CALL PUT('SPAM', 'ES',  ES)
      CALL PUT('SPAM', 'ET',  ET)

!***********************************************************************
!***********************************************************************
!     DAILY RATE CALCULATIONS
!***********************************************************************
      ELSEIF (DYNAMIC .EQ. RATE) THEN
!-----------------------------------------------------------------------
      SWDELTX = 0.0
      CALL STEMP(CONTROL, ISWITCH,
     &    SOILPROP, SRAD, SW, TAVG, TMAX, XLAT, TAV, TAMP,!Input
     &    SRFTEMP, ST)                                    !Output

!-----------------------------------------------------------------------
!     POTENTIAL ROOT WATER UPTAKE
!-----------------------------------------------------------------------
      IF (ISWWAT .EQ. 'Y') THEN
!       Calculate the availability of soil water for use in SOILEV.
        DO L = 1, NLAYR
          SW_AVAIL(L) = MAX(0.0, SW(L) + SWDELTS(L) + SWDELTU(L))
        ENDDO

!       These processes are done by ETPHOT for hourly (Zonal) energy
!       balance method.
        IF (MEEVP .NE. 'Z') THEN
!-----------------------------------------------------------------------
!         POTENTIAL EVAPOTRANSPIRATION
!-----------------------------------------------------------------------
          IF (FLOOD .GT. 0.0) THEN
            ! Set albedo to 0.08 under flooded conditions
            ! US - change to 0.05 Feb2004
            ET_ALB = 0.05
          ELSE
            ET_ALB = MSALB
          ENDIF

          CALL PET(CONTROL, 
     &      ET_ALB, XHLAI, MEEVP, WEATHER,  !Input for all
     &      EORATIO, !Needed by Penman-Monteith
     &      CANHT,   !Needed by dynamic Penman-Monteith
     &      EO)      !Output

!-----------------------------------------------------------------------
!         POTENTIAL SOIL EVAPORATION
!-----------------------------------------------------------------------
!         05/26/2007 CHP/MJ Use XLAI instead of XHLAI 
!         This was important for Canegro and affects CROPGRO crops
!             only very slightly (max 0.5% yield diff for one peanut
!             experiment).  No difference to other crop models.
          CALL PSE(EO, KSEVAP, XLAI, EOS)

!         Initialize soil, mulch and flood evaporation
          ES = 0.; EM = 0.; EF = 0.

!-----------------------------------------------------------------------
!         ACTUAL SOIL OR FLOOD EVAPORATION
!-----------------------------------------------------------------------
          IF (FLOOD .GT. 1.E-4) THEN
            CALL FLOOD_EVAP(XLAI, EO, EF)

          ELSE
!           Mulch evaporation unless switched off. This modifies EOS
!           IF (INDEX('RSN',MEINF) .LE. 0) THEN
            IF (INDEX('RSML',MEINF) > 0) THEN   
              CALL MULCH_EVAP(DYNAMIC, MULCH, EOS, EM)
            ENDIF

            SELECT CASE(MESEV)
!           ------------------------
            CASE ('R')  !Ritchie soil evaporation routine
!             Calculate the availability of soil water for use in SOILEV.
              DO L = 1, NLAYR
                SW_AVAIL(L) = MAX(0.0, SW(L) + SWDELTS(L) + SWDELTU(L))
              ENDDO
              CALL SOILEV(RATE,
     &          DLAYR, DUL, EOS, LL, SW,                  !Input
     &          SW_AVAIL(1), U, WINF,                     !Input
     &          ES)                                       !Output

!           ------------------------
            CASE DEFAULT !SALUS soil evaporation routine is default
!             Note that this routine calculates UPFLOW, unlike the SOILEV.
!             Calculate the availability of soil water for use in SOILEV.
              CALL ESR_SoilEvap(
     &          EOS, SOILPROP, SW, SWDELTS,               !Input
     &          ES, ES_LYR, SWDELTU, UPFLOW)              !Output
            END SELECT
!           ------------------------
          ENDIF

!-----------------------------------------------------------------------
!         ACTUAL TRANSPIRATION
!-----------------------------------------------------------------------
          IF (XHLAI .GT. 0.0) THEN
            IF (FLOOD .GT. 0.0) THEN
              !Use flood evaporation rate
              CALL TRANS (RATE, 
     &          CO2, CROP, EO, EF, KTRANS, TAVG, WINDSP, XHLAI, !Input
     &          EOP)                                            !Output
            ELSE
              !Use soil evaporation rate
              CALL TRANS(RATE, 
     &          CO2, CROP, EO, ES, KTRANS, TAVG, WINDSP, XHLAI, !Input
     &          EOP)                                            !Output
            ENDIF
          ELSE
            EOP = 0.0
          ENDIF

!         Calculate potential root water uptake rate for each soil layer
!         and total potential water uptake rate.
          IF (XHLAI .GT. 0.0) THEN
!           temp chp 8/10/2009
!           use MESIC to trigger hourly ROOTWU_HR
            SELECT CASE(CONTROL % MESIC)
            CASE ('H')
              CALL ROOTWU_HR(RATE,  
     &         DLAYR, EOP, ES_LYR, LL, NLAYR, RLV,        !Input
     &         SAT, SW, WEATHER,                          !Input
     &         EP, RWU, SWDELTX, SWFAC, TRWU, TRWUP, TURFAC) !Output

            CASE DEFAULT
              CALL ROOTWU(RATE,
     &          DLAYR, LL, NLAYR, RLV, SAT, SW,           !Input
     &          RWU, TRWUP)                               !Output

              CALL WaterStress(EOP, RWUEP1, TRWUP, SWFAC, TURFAC)
            END SELECT
         ELSE
            RWU   = 0.0
            TRWUP = 0.0
          ENDIF

          IF (XHLAI .GT. 1.E-4 .AND. EOP .GT. 1.E-4) THEN
            !These calcs replace the old SWFACS subroutine
            !Stress factors now calculated as needed in PLANT routines.
            EP = MIN(EOP, TRWUP*10.)
          ELSE
            EP = 0.0
          ENDIF
        ENDIF
      ENDIF

!-----------------------------------------------------------------------
!     ALTERNATE CALL TO ENERGY BALANCE ROUTINES
!-----------------------------------------------------------------------
      IF (CROP .NE. 'FA') THEN
        IF (MEEVP .EQ. 'Z' .OR.
     &        (MEPHO .EQ. 'L' .AND. XHLAI .GT. 0.0)) THEN
          !ETPHOT called for photosynthesis only
          !    (MEPHO = 'L' and MEEVP <> 'Z')
          !or for both photosynthesis and evapotranspiration
          !   (MEPHO = 'L' and MEEVP = 'Z').
          CALL ETPHOT(CONTROL, ISWITCH,
     &      RLV, SOILPROP, ST, SW, WEATHER, XHLAI,        !Input
     &      EOP, EP, ES, RWU, TRWUP)                      !Output

          IF (MEEVP == 'Z') THEN
            CALL WaterStress(EOP, RWUEP1, TRWUP, SWFAC, TURFAC) 
          ENDIF
        ENDIF

!-----------------------------------------------------------------------
!       ACTUAL ROOT WATER EXTRACTION
!-----------------------------------------------------------------------
        IF (ISWWAT .EQ. 'Y') THEN
!         Adjust available soil water for evaporation
          SELECT CASE(MESEV)
          CASE ('R') !
            SW_AVAIL(1) = MAX(0.0, SW_AVAIL(1) - 0.1 * ES / DLAYR(1))

          CASE DEFAULT
            DO L = 1, NLAYR
              SW_AVAIL(L) = MAX(0.0,SW_AVAIL(L) -0.1*ES_LYR(L)/DLAYR(L))
            ENDDO
          END SELECT

          IF (control % MESIC .NE. 'H') THEN
!           For hourly RWU, already scaled by EP
C           Calculate actual soil water uptake and transpiration rates
            CALL XTRACT(
     &      NLAYR, DLAYR, LL, SW, SW_AVAIL, TRWUP,        !Input
     &      EP, RWU,                                      !Input/Output
     &      SWDELTX, TRWU)                                !Output
          ENDIF
        ENDIF   !ISWWAT = 'Y'
      ENDIF

!     Transfer computed value of potential floodwater evaporation to
!     flood variable.
      FLOODWAT % EF = EF

!     Transfer data to storage routine
      CALL PUT('SPAM', 'EF',  EF)
      CALL PUT('SPAM', 'EM',  EM)
      CALL PUT('SPAM', 'EO',  EO)
      CALL PUT('SPAM', 'EP',  EP)
      CALL PUT('SPAM', 'ES',  ES)
      CALL PUT('SPAM', 'UH2O',RWU)

!***********************************************************************
!***********************************************************************
!     DAILY INTEGRATION
!***********************************************************************
      ELSEIF (DYNAMIC .EQ. INTEGR) THEN
!-----------------------------------------------------------------------
      IF (ISWWAT .EQ. 'Y') THEN
!       Perform daily summation of water balance variables.
        ET  = ES  + EM + EP + EF
        CEF = CEF + EF
        CEM = CEM + EM
        CEO = CEO + EO
        CEP = CEP + EP
        CES = CES + ES
        CET = CET + ET
      ENDIF

      IF (IDETW .EQ. 'Y') THEN
        CALL OPSPAM(CONTROL, ISWITCH, FLOODWAT,
     &    CEF, CEM, CEO, CEP, CES, CET, EF, EM, 
     &    EO, EOP, EOS, EP, ES, ET, TMAX, TMIN, TRWUP, SRAD,
     &    ES_LYR, SOILPROP)
      ENDIF

!     Transfer data to storage routine
      CALL PUT('SPAM', 'CEF', CEF)
      CALL PUT('SPAM', 'CEM', CEM)
      CALL PUT('SPAM', 'CEO', CEO)
      CALL PUT('SPAM', 'CEP', CEP)
      CALL PUT('SPAM', 'CES', CES)
      CALL PUT('SPAM', 'CET', CET)
      CALL PUT('SPAM', 'ET',  ET)

!***********************************************************************
!***********************************************************************
!     OUTPUT - daily output
!***********************************************************************
      ELSEIF (DYNAMIC .EQ. OUTPUT) THEN
C-----------------------------------------------------------------------
!     Flood water evaporation can be modified by Paddy_Mgmt routine.
      EF = FLOODWAT % EF

      CALL STEMP(CONTROL, ISWITCH,
     &    SOILPROP, SRAD, SW, TAVG, TMAX, XLAT, TAV, TAMP,!Input
     &    SRFTEMP, ST)                                    !Output

      CALL OPSPAM(CONTROL, ISWITCH, FLOODWAT,
     &    CEF, CEM, CEO, CEP, CES, CET, EF, EM, 
     &    EO, EOP, EOS, EP, ES, ET, TMAX, TMIN, TRWUP, SRAD,
     &    ES_LYR, SOILPROP)

      IF (CROP .NE. 'FA' .AND. MEPHO .EQ. 'L') THEN
        CALL ETPHOT(CONTROL, ISWITCH,
     &    RLV, SOILPROP, ST, SW, WEATHER, XHLAI,          !Input
     &    EOP, EP, ES, RWU, TRWUP)                        !Output
      ENDIF

!      CALL OPSTRESS(CONTROL, ET=ET, EP=EP)

!***********************************************************************
!***********************************************************************
!     SEASEND - seasonal output
!***********************************************************************
      ELSEIF (DYNAMIC .EQ. SEASEND) THEN
C-----------------------------------------------------------------------
      CALL OPSPAM(CONTROL, ISWITCH, FLOODWAT,
     &    CEF, CEM, CEO, CEP, CES, CET, EF, EM, 
     &    EO, EOP, EOS, EP, ES, ET, TMAX, TMIN, TRWUP, SRAD,
     &    ES_LYR, SOILPROP)

      CALL STEMP(CONTROL, ISWITCH,
     &    SOILPROP, SRAD, SW, TAVG, TMAX, XLAT, TAV, TAMP,!Input
     &    SRFTEMP, ST)                                    !Output

      IF (MEPHO .EQ. 'L') THEN
        CALL ETPHOT(CONTROL, ISWITCH,
     &    RLV, SOILPROP, ST, SW, WEATHER, XHLAI,          !Input
     &    EOP, EP, ES, RWU, TRWUP)                        !Output
      ENDIF

!     Transfer data to storage routine
      CALL PUT('SPAM', 'CEF', CEF)
      CALL PUT('SPAM', 'CEM', CEM)
      CALL PUT('SPAM', 'CEO', CEO)
      CALL PUT('SPAM', 'CEP', CEP)
      CALL PUT('SPAM', 'CES', CES)
      CALL PUT('SPAM', 'CET', CET)
      CALL PUT('SPAM', 'ET',  ET)

!      CALL OPSTRESS(CONTROL, ET=ET, EP=EP)

!***********************************************************************
!***********************************************************************
!     END OF DYNAMIC IF CONSTRUCT
!***********************************************************************
      ENDIF
!-----------------------------------------------------------------------
      RETURN
      END SUBROUTINE SPAM

!-----------------------------------------------------------------------
!     VARIABLE DEFINITIONS: (updated 12 Feb 2004)
!-----------------------------------------------------------------------
! CANHT       Canopy height (m)
! CEF         Cumulative seasonal evaporation from floodwater surface (mm)
! CEM         Cumulative evaporation from surface mulch layer (mm)
! CEO         Cumulative potential evapotranspiration (mm)
! CEP         Cumulative transpiration (mm)
! CES         Cumulative evaporation (mm)
! CET         Cumulative evapotranspiration (mm)
! CLOUDS      Relative cloudiness factor (0-1) 
! CO2         Atmospheric carbon dioxide concentration
!              (�mol[CO2] / mol[air])
! CONTROL     Composite variable containing variables related to control 
!               and/or timing of simulation.    See Appendix A. 
! CROP        Crop identification code 
! DLAYR(L)    Thickness of soil layer L (cm)
! DUL(L)      Volumetric soil water content at Drained Upper Limit in soil 
!               layer L (cm3[water]/cm3[soil])
! EF          Evaporation rate from flood surface (mm / d)
! EM          Evaporation rate from surface mulch layer (mm / d)
! EO          Potential evapotranspiration rate (mm/d)
! EOP         Potential plant transpiration rate (mm/d)
! EORATIO     Ratio of increase in potential evapotranspiration with 
!               increase in LAI (up to LAI=6.0) for use with FAO-56 Penman 
!               reference potential evapotranspiration. 
! EOS         Potential rate of soil evaporation (mm/d)
! EP          Actual plant transpiration rate (mm/d)
! ES          Actual soil evaporation rate (mm/d)
! ET          Actual evapotranspiration rate (mm/d)
! FLOOD       Current depth of flooding (mm)
! FLOODWAT    Composite variable containing information related to bund 
!               management. Structure of variable is defined in 
!               ModuleDefs.for. 
! IDETW       Y=detailed water balance output, N=no detailed output 
! ISWITCH     Composite variable containing switches which control flow of 
!               execution for model.  The structure of the variable 
!               (SwitchType) is defined in ModuleDefs.for. 
! ISWWAT      Water simulation control switch (Y or N) 
! KSEVAP      Light extinction coefficient used for computation of soil 
!               evaporation 
! KTRANS      Light extinction coefficient used for computation of plant 
!               transpiration 
! LL(L)       Volumetric soil water content in soil layer L at lower limit
!              (cm3 [water] / cm3 [soil])
! MEEVP       Method of evapotranspiration ('P'=Penman, 
!               'R'=Priestly-Taylor, 'Z'=Zonal) 
! MEPHO       Method for photosynthesis computation ('C'=Canopy or daily, 
!               'L'=hedgerow or hourly) 
! NLAYR       Actual number of soil layers 
! RLV(L)      Root length density for soil layer L (cm[root] / cm3[soil])
! RWU(L)      Root water uptake from soil layer L (cm/d)
! MSALB       Soil albedo with mulch and soil water effects (fraction)
! SAT(L)      Volumetric soil water content in layer L at saturation
!              (cm3 [water] / cm3 [soil])
! SOILPROP    Composite variable containing soil properties including bulk 
!               density, drained upper limit, lower limit, pH, saturation 
!               water content.  Structure defined in ModuleDefs. 
! SRAD        Solar radiation (MJ/m2-d)
! SRFTEMP     Temperature of soil surface litter (�C)
! ST(L)       Soil temperature in soil layer L (�C)
! SUMES1      Cumulative soil evaporation in stage 1 (mm)
! SUMES2      Cumulative soil evaporation in stage 2 (mm)
! SW(L)       Volumetric soil water content in layer L
!              (cm3 [water] / cm3 [soil])
! SW_AVAIL(L) Soil water content in layer L available for evaporation, 
!               plant extraction, or movement through soil
!               (cm3 [water] / cm3 [soil])
! SWDELTS(L)  Change in soil water content due to drainage in layer L
!              (cm3 [water] / cm3 [soil])
! SWDELTU(L)  Change in soil water content due to evaporation and/or upward 
!               flow in layer L (cm3 [water] / cm3 [soil])
! SWDELTX(L)  Change in soil water content due to root water uptake in 
!               layer L (cm3 [water] / cm3 [soil])
! T           Number of days into Stage 2 evaporation (WATBAL); or time 
!               factor for hourly temperature calculations 
! TA          Daily normal temperature (�C)
! TAMP        Amplitude of temperature function used to calculate soil 
!               temperatures (�C)
! TAV         Average annual soil temperature, used with TAMP to calculate 
!               soil temperature. (�C)
! TAVG        Average daily temperature (�C)
! TMAX        Maximum daily temperature (�C)
! TMIN        Minimum daily temperature (�C)
! TRWU        Actual daily root water uptake over soil profile (cm/d)
! TRWUP       Potential daily root water uptake over soil profile (cm/d)
! U           Evaporation limit (cm)
! WINDSP      Wind speed at 2m (km/d)
! WINF        Water available for infiltration - rainfall minus runoff plus 
!               net irrigation (mm / d)
! XHLAI       Healthy leaf area index (m2[leaf] / m2[ground])
! XLAT        Latitude (deg.)
!-----------------------------------------------------------------------
!     END SUBROUTINE SPAM
!-----------------------------------------------------------------------

