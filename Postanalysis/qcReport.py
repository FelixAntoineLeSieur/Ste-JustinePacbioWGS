import sys,os

"""
Here we want to produce a qcReport including:
- Gender concordance
- Identity validation with short reads through 44 SNPs
- Parental concordance (PEDDY)
- Number of chromosomes
- Level of consanguinity through hom/het %
"""
if __name__ == "__main__":
	#First step is to obtain the file containing the output paths
	