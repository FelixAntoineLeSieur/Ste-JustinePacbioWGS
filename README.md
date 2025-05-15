# Ste-JustinePacbioWGS
Pacbio data processing, including Preanalysis, WGS Analysis and Post-analysis


We describe here a workflow for analyzing and processing data received from the Revio PacBio sequencer acquired by the CHU Sainte-Justine. 

## Data processing
![Diag](https://github.com/user-attachments/assets/488dfa31-3974-43fd-ba15-68190e756015)
Once out of the sequencer, the long-read sequencing data is automatically transfered on a in-house smrtlink server, for temporary storage. 
Since storage and computing resources are limited on this server, we transfer the data to a cluster of the Alliance, [Narval](https://docs.alliancecan.ca/wiki/Narval).
\\
From there, we process the data using PacBio's [WGS pipeline](https://github.com/PacificBiosciences/HiFi-human-WGS-WDL). Note that I have my own fork of this pipeline [here](https://github.com/FelixAntoineLeSieur/HiFi-human-WGS-WDL). It contains some minor changes aimed at making the pipeline usable in the Narval environment.
\\
Once the data has been processed by the WGS pipeline, we want to setup tertiary analysis, primarily through the GeneYX website.
