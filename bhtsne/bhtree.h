class BHTree {
   private:

   public:
    BHTree(int num_points);
    ~BHTree();

    void compute_nonedge_forces(float* points, int num_points, float* neg_forces, float* norm);
};